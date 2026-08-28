const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const fs = require('fs');
const path = require('path');
const app = express();
app.set('trust proxy', 1);
app.use(helmet());
app.use(cors());
app.use(compression());
app.use(rateLimit({ windowMs: 60_000, max: 300 }));
app.use(express.json({ limit: '8kb' })); // default tiny limit for endpoints that don't opt in
// Larger body limit for endpoints that carry base64 media (avatars, images, files, stories, group keys).
// Files travel as base64 inside JSON, which inflates them by ~33%: the client's
// 50 MB ceiling was already producing ~67 MB bodies against a 60 MB limit, so
// anything over ~45 MB failed with 413. Photon tier raises the ceiling to 80 MB
// (~107 MB encoded), hence 120 MB here.
// Memory cost is real — express buffers the whole body — so a small instance
// should not be asked to serve many concurrent uploads of this size.
const bigBody = express.json({ limit: '120mb' });
// Small json limit for text-only endpoints that still want their own parser (skips the global 8kb).
const smallBody = express.json({ limit: '32kb' });
const medBody = express.json({ limit: '256kb' });

// Stricter limit for AI endpoint: 20 requests/hour per IP.
const aiLimiter = rateLimit({ windowMs: 60 * 60 * 1000, max: 20 });

// --- In-memory store ---
const users = new Map();
const requests = new Map();
const accepted = new Map();
const chats = new Map();
const groups = new Map();
const typingMap = new Map();
const registry = new Map();
const chatReads = new Map();
const chatReactions = new Map(); // `${chatKey}_${msgId}` -> {emoji: [fipId,...]}
const reactionsByChat = new Map(); // chatKey -> Set(msgId) — index for O(1) fanout
const userNotifs = new Map();
const groupAnnouncements = new Map();
const stories = new Map();
const deviceLinkRequests = new Map();
const deviceLinkStatus = new Map();
const deviceActivities = new Map();
const deviceBans = new Map();
const codeToFipId = new Map();
const groupCodeIndex = new Map();
const deviceIdToRequester = new Map();
// Paid tiers live here and ONLY here. Every user runs their own copy of this
// server, so a tier stored on a user's own instance could be self-granted with a
// one-line edit. Clients read tiers from the bridge deployment, never from the
// profile server of the person they are looking at.
// fipId -> { tier, color, expiresAt, fakeName, fakeActive }
const tiers = new Map();
// Dedupe recent auto-notifs: `${from}->${to}` -> lastTs
const lastAutoNotif = new Map();

// --- Caps to bound growth ---
const MAX_REQUESTS_PER_USER = 200;
const MAX_JOIN_REQUESTS = 200;
const MAX_STORIES_PER_USER = 50;
const MAX_TYPING_KEYS = 5000;
const MAX_REGISTRY = 100_000;

// Normalize actor: legacy clients only send `from` / `fromFipId` / `fipId` /
// `myFipId`. Populate `req.body.actor` from the first matching key so every
// downstream `req.body.actor === X` check keeps working without exception.
app.use((req, res, next) => {
  if (req.body) {
    if (!req.body.actor) {
      req.body.actor = req.body.from
        || req.body.fromFipId
        || req.body.fipId
        || req.body.myFipId
        || req.body.requesterFipId
        || null;
    }
    // Legacy alias: client historically sends `from` for DM sends; server
    // destructures `fromFipId`. Populate one from the other so old and new
    // clients both work without per-endpoint churn.
    if (!req.body.fromFipId && req.body.from) req.body.fromFipId = req.body.from;
    if (!req.body.from && req.body.fromFipId) req.body.from = req.body.fromFipId;
  }
  next();
});

// --- Auth helpers ---
// The client identifies itself via either `actor` or `from`/`fromFipId`
// depending on the endpoint. Accept whichever matches — old clients that
// only send `from` still work; new clients that also send `actor` still
// work. Only clients that identify as someone else are rejected.
function _bodyActor(req) {
  const b = req.body || {};
  return b.actor || b.from || b.fromFipId || null;
}
function requireOwner(req, res, group) {
  const a = _bodyActor(req);
  if (a !== group.ownerFipId) { res.sendStatus(403); return false; }
  return true;
}
function requireMessageAuthor(req, res, msg) {
  const a = _bodyActor(req);
  if (a !== msg.from) { res.sendStatus(403); return false; }
  return true;
}
function requireActor(req, res, expected) {
  const a = _bodyActor(req);
  if (a !== expected) { res.sendStatus(403); return false; }
  return true;
}
function isNonEmptyString(v, max = 8000) {
  return typeof v === 'string' && v.length > 0 && v.length <= max;
}
function isMember(g, fipId) {
  return !!(g && g.members && g.members.find(m => m.fipId === fipId));
}

// Chat keys come from chatKeyFor() in lib/fip.dart: the two fipIds sorted and
// joined with a DOUBLE underscore. fipIds are themselves `fip_<hex>`, i.e. they
// contain a single underscore — so splitting the key on '_' shreds them and no
// participant ever matches. That made every authenticated /chat endpoint answer
// 403 to its own legitimate caller. Split on the real separator instead.
function chatHasParticipant(chatKey, fipId) {
  if (typeof chatKey !== 'string' || typeof fipId !== 'string' || !fipId) return false;
  if (chatKey.split('__').includes(fipId)) return true;
  // Tolerate keys built by older clients that used a single separator, while
  // still requiring the id to occupy a whole segment.
  return chatKey === fipId
    || chatKey.startsWith(`${fipId}_`)
    || chatKey.endsWith(`_${fipId}`);
}

// --- Persistence ---
const SNAPSHOT_FILE = process.env.SNAPSHOT_FILE || '/tmp/photon-snapshot.json';

function mapToObj(m) {
  const o = {};
  for (const [k, v] of m) o[k] = v instanceof Set ? [...v] : v;
  return o;
}

function loadSnapshot() {
  try {
    if (!fs.existsSync(SNAPSHOT_FILE)) return;
    const raw = JSON.parse(fs.readFileSync(SNAPSHOT_FILE, 'utf8'));
    for (const [k, v] of Object.entries(raw.users || {})) { users.set(k, v); if (v && v.code) codeToFipId.set(v.code, k); }
    for (const [k, v] of Object.entries(raw.requests || {})) requests.set(k, v);
    for (const [k, v] of Object.entries(raw.accepted || {})) accepted.set(k, new Set(v));
    for (const [k, v] of Object.entries(raw.chats || {})) chats.set(k, v);
    for (const [k, v] of Object.entries(raw.groups || {})) { groups.set(k, v); if (v && v.groupCode) groupCodeIndex.set(v.groupCode, k); }
    for (const [k, v] of Object.entries(raw.registry || {})) registry.set(k, v);
    for (const [k, v] of Object.entries(raw.tiers || {})) tiers.set(k, v);
    for (const [k, v] of Object.entries(raw.chatReads || {})) chatReads.set(k, v);
    for (const [k, v] of Object.entries(raw.chatReactions || {})) chatReactions.set(k, v);
    // The index is persisted directly. It used to be rebuilt by splitting the
    // composite `${chatKey}_${msgId}` key at the last underscore, but msgIds
    // are themselves `${ts}_${rand}` — so the split landed inside the msgId and
    // every reaction became unreachable after a restart.
    for (const [k, v] of Object.entries(raw.reactionsByChat || {})) reactionsByChat.set(k, new Set(v));
    for (const [k, v] of Object.entries(raw.userNotifs || {})) userNotifs.set(k, v);
    for (const [k, v] of Object.entries(raw.groupAnnouncements || {})) groupAnnouncements.set(k, v);
    for (const [k, v] of Object.entries(raw.stories || {})) stories.set(k, v);
    for (const [k, v] of Object.entries(raw.deviceLinkRequests || {})) deviceLinkRequests.set(k, v);
    for (const [k, v] of Object.entries(raw.deviceLinkStatus || {})) deviceLinkStatus.set(k, v);
    for (const [k, v] of Object.entries(raw.deviceActivities || {})) deviceActivities.set(k, v);
    for (const [k, v] of Object.entries(raw.deviceBans || {})) deviceBans.set(k, new Set(v));
    for (const [k, v] of Object.entries(raw.deviceIdToRequester || {})) deviceIdToRequester.set(k, v);
    console.log(`Snapshot loaded from ${SNAPSHOT_FILE}`);
  } catch (e) {
    console.error('Snapshot load failed:', e.message);
  }
}

function saveSnapshot() {
  try {
    const data = {
      users: mapToObj(users),
      requests: mapToObj(requests),
      accepted: mapToObj(accepted),
      chats: mapToObj(chats),
      groups: mapToObj(groups),
      registry: mapToObj(registry),
      tiers: mapToObj(tiers),
      chatReads: mapToObj(chatReads),
      chatReactions: mapToObj(chatReactions),
      reactionsByChat: mapToObj(reactionsByChat),
      userNotifs: mapToObj(userNotifs),
      groupAnnouncements: mapToObj(groupAnnouncements),
      stories: mapToObj(stories),
      deviceLinkRequests: mapToObj(deviceLinkRequests),
      deviceLinkStatus: mapToObj(deviceLinkStatus),
      deviceActivities: mapToObj(deviceActivities),
      deviceBans: mapToObj(deviceBans),
      deviceIdToRequester: mapToObj(deviceIdToRequester),
    };
    const tmp = SNAPSHOT_FILE + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(data));
    fs.renameSync(tmp, SNAPSHOT_FILE);
  } catch (e) {
    console.error('Snapshot save failed:', e.message);
  }
}

loadSnapshot();
setInterval(saveSnapshot, 30_000);

// Periodic janitor: TTL sweeps that keep memory bounded.
setInterval(() => {
  const now = Date.now();
  // Typing entries older than 10s — drop entire key if empty.
  for (const [k, list] of typingMap) {
    const fresh = list.filter(t => now - (t.ts || 0) < 10_000);
    if (fresh.length === 0) typingMap.delete(k);
    else if (fresh.length !== list.length) typingMap.set(k, fresh);
  }
  // Stories: prune expired.
  for (const [k, list] of stories) {
    const fresh = list.filter(s => (s.expiresAt || 0) > now);
    if (fresh.length === 0) stories.delete(k);
    else if (fresh.length !== list.length) stories.set(k, fresh);
  }
  // Notifs: prune >10 min old.
  for (const [k, list] of userNotifs) {
    const fresh = list.filter(n => (n.ts || 0) > now - 10 * 60 * 1000);
    if (fresh.length === 0) userNotifs.delete(k);
    else if (fresh.length !== list.length) userNotifs.set(k, fresh);
  }
  // Auto-notif dedupe map: prune entries older than 5 min.
  for (const [k, ts] of lastAutoNotif) {
    if (ts < now - 5 * 60 * 1000) lastAutoNotif.delete(k);
  }
}, 60_000);

function rand(n) {
  return Math.floor(Math.random() * Math.pow(10, n)).toString().padStart(n, '0');
}

function msgId() {
  return `${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
}

// --- Presence ---
app.post('/presence', bigBody, (req, res) => {
  const { fipId, code, name, publicKey, serverUrl, statusMsg, avatar, bio } = req.body;
  if (!isNonEmptyString(fipId, 128)) return res.sendStatus(400);
  // v9.2: HD avatars — ~300KB raw → 400KB base64. Cap at 500KB.
  if (avatar && typeof avatar === 'string' && avatar.length > 500_000) {
    return res.status(413).json({ error: 'avatar too large' });
  }
  const prev = users.get(fipId);
  if (prev && prev.code && prev.code !== code) codeToFipId.delete(prev.code);
  users.set(fipId, {
    code: typeof code === 'string' ? code.slice(0, 32) : '',
    name: typeof name === 'string' ? name.slice(0, 100) : '',
    publicKey: typeof publicKey === 'string' ? publicKey.slice(0, 4000) : '',
    serverUrl: typeof serverUrl === 'string' ? serverUrl.slice(0, 500) : '',
    statusMsg: typeof statusMsg === 'string' ? statusMsg.slice(0, 200) : '',
    avatar: avatar || '',
    bio: typeof bio === 'string' ? bio.slice(0, 500) : '',
    lastSeen: Date.now(),
  });
  if (code) codeToFipId.set(code, fipId);
  res.sendStatus(200);
});

app.get('/lookup/:code', (req, res) => {
  const fipId = codeToFipId.get(req.params.code);
  if (fipId) {
    const u = users.get(fipId);
    if (u) return res.json({ fipId, ...u });
  }
  res.sendStatus(404);
});

app.get('/profile/:fipId', (req, res) => {
  const u = users.get(req.params.fipId);
  if (!u) return res.sendStatus(404);
  res.json({ fipId: req.params.fipId, name: u.name, code: u.code, publicKey: u.publicKey || '', statusMsg: u.statusMsg || '', avatar: u.avatar || '', bio: u.bio || '', lastSeen: u.lastSeen || 0 });
});

// --- Friend requests ---
app.post('/requests/:toFipId', medBody, (req, res) => {
  const { toFipId } = req.params;
  const { fromFipId, fromCode, fromName, fromServerUrl, fromPublicKey, bio } = req.body;
  if (!isNonEmptyString(fromFipId, 128) || !isNonEmptyString(toFipId, 128)) return res.sendStatus(400);
  if (fromFipId === toFipId) return res.sendStatus(400);
  if (!requests.has(toFipId)) requests.set(toFipId, []);
  const list = requests.get(toFipId);
  if (list.length >= MAX_REQUESTS_PER_USER) return res.status(429).json({ error: 'too many pending requests' });
  if (!list.find(r => r.fromFipId === fromFipId)) {
    list.push({
      fromFipId,
      fromCode: typeof fromCode === 'string' ? fromCode.slice(0, 32) : '',
      fromName: typeof fromName === 'string' ? fromName.slice(0, 100) : '',
      fromServerUrl: typeof fromServerUrl === 'string' ? fromServerUrl.slice(0, 500) : '',
      fromPublicKey: typeof fromPublicKey === 'string' ? fromPublicKey.slice(0, 4000) : '',
      bio: typeof bio === 'string' ? bio.slice(0, 500) : '',
      ts: Date.now(),
    });
  }
  res.sendStatus(200);
});

app.get('/requests/:toFipId', (req, res) => {
  res.json(requests.get(req.params.toFipId) || []);
});

app.post('/accept', (req, res) => {
  const { myFipId, otherFipId, actor } = req.body;
  if (!isNonEmptyString(myFipId, 128) || !isNonEmptyString(otherFipId, 128)) return res.sendStatus(400);
  if (actor !== myFipId) return res.sendStatus(403);
  if (!accepted.has(myFipId)) accepted.set(myFipId, new Set());
  accepted.get(myFipId).add(otherFipId);
  const list = requests.get(myFipId);
  if (list) requests.set(myFipId, list.filter(r => r.fromFipId !== otherFipId));
  res.sendStatus(200);
});

app.get('/accepted/:myFipId', (req, res) => {
  res.json([...(accepted.get(req.params.myFipId) || [])]);
});

// --- Active check ---
app.post('/active', (req, res) => {
  const { fipIds } = req.body;
  if (!Array.isArray(fipIds)) return res.json([]);
  const slice = fipIds.slice(0, 500).filter(id => typeof id === 'string');
  res.json(slice.filter(id => users.has(id)));
});

// --- Direct messages ---
app.get('/chat/:chatKey', (req, res) => {
  res.json(chats.get(req.params.chatKey) || []);
});

app.post('/chat/:chatKey', bigBody, (req, res) => {
  const key = req.params.chatKey;
  const { fromFipId, toFipId, fromName, text, actor } = req.body;
  if (!isNonEmptyString(fromFipId, 128)) return res.sendStatus(400);
  // Only the sender may post as themselves.
  if (actor !== fromFipId) return res.sendStatus(403);
  // ChatKey must include the sender (chatKeys are `${a}__${b}`, sorted).
  if (!chatHasParticipant(key, fromFipId)) return res.sendStatus(403);
  if (typeof text === 'string' && text.length > 8000) {
    return res.status(413).json({ error: 'text too long' });
  }
  if (!chats.has(key)) chats.set(key, []);
  const msgs = chats.get(key);
  const id = msgId();
  // Whitelist fields rather than spreading arbitrary body.
  const { attachment, replyTo, ts, type, imageData, nsfw, fileName, fileData, fileSize } = req.body;
  msgs.push({
    // Store both `from` and `fromFipId` so downstream author checks
    // (delete/edit) and client code that reads either name work.
    from: fromFipId, fromFipId, toFipId, fromName, text: typeof text === 'string' ? text : '',
    attachment, replyTo, ts: ts || Date.now(), type,
    imageData, nsfw, fileName, fileData, fileSize,
    msgId: id,
  });
  if (msgs.length > 200) msgs.splice(0, msgs.length - 200);
  // Auto-notify recipient (deduped: at most one per (from,to) per 30s).
  if (toFipId && fromName) {
    const dedupeKey = `${fromFipId}->${toFipId}`;
    const now = Date.now();
    const last = lastAutoNotif.get(dedupeKey) || 0;
    if (now - last > 30_000) {
      lastAutoNotif.set(dedupeKey, now);
      if (!userNotifs.has(toFipId)) userNotifs.set(toFipId, []);
      const nlist = userNotifs.get(toFipId);
      // Locale-neutral tags — the client renders them in the user's own
      // language. Sending Turkish text here showed Turkish notifications to
      // users who had switched the app to another language.
      nlist.push({ title: '__NEW_MESSAGE__', body: '__NEW_MESSAGE_FROM__', bodyName: fromName, ts: now });
      if (nlist.length > 50) nlist.splice(0, nlist.length - 50);
    }
  }
  res.json({ msgId: id });
});

app.delete('/chat/:chatKey', medBody, (req, res) => {
  const key = req.params.chatKey;
  const actor = req.body && req.body.actor;
  if (!chatHasParticipant(key, actor)) return res.sendStatus(403);
  chats.delete(key);
  // Clear reactions index for this chat.
  const idx = reactionsByChat.get(key);
  if (idx) {
    for (const mid of idx) chatReactions.delete(`${key}_${mid}`);
    reactionsByChat.delete(key);
  }
  res.sendStatus(200);
});

app.delete('/chat/:chatKey/msg/:msgId', medBody, (req, res) => {
  const msgs = chats.get(req.params.chatKey);
  if (!msgs) return res.sendStatus(404);
  const idx = msgs.findIndex(m => m.msgId === req.params.msgId);
  if (idx === -1) return res.sendStatus(404);
  const msg = msgs[idx];
  const author = msg.from || msg.fromFipId;
  if (!req.body || req.body.actor !== author) return res.sendStatus(403);
  msgs[idx] = { ...msg, text: '', deleted: true };
  res.sendStatus(200);
});

app.put('/chat/:chatKey/msg/:msgId', medBody, (req, res) => {
  const msgs = chats.get(req.params.chatKey);
  if (!msgs) return res.sendStatus(404);
  const idx = msgs.findIndex(m => m.msgId === req.params.msgId);
  if (idx === -1) return res.sendStatus(404);
  const msg = msgs[idx];
  const author = msg.from || msg.fromFipId;
  if (!req.body || req.body.actor !== author) return res.sendStatus(403);
  if (typeof req.body.text !== 'string' || req.body.text.length > 8000) return res.sendStatus(400);
  msgs[idx] = { ...msg, text: req.body.text, edited: true };
  res.sendStatus(200);
});

// --- Reactions ---
app.post('/chat/:chatKey/msg/:msgId/react', (req, res) => {
  const chatKey = req.params.chatKey;
  const mid = req.params.msgId;
  const key = `${chatKey}_${mid}`;
  const { fipId, emoji, actor } = req.body;
  if (!isNonEmptyString(fipId, 128) || !isNonEmptyString(emoji, 32)) return res.sendStatus(400);
  if (actor !== fipId) return res.sendStatus(403);
  if (!chatHasParticipant(chatKey, fipId)) return res.sendStatus(403);
  if (!chatReactions.has(key)) chatReactions.set(key, {});
  const r = chatReactions.get(key);
  if (!r[emoji]) r[emoji] = [];
  const idx = r[emoji].indexOf(fipId);
  if (idx === -1) r[emoji].push(fipId); else r[emoji].splice(idx, 1);
  if (r[emoji].length === 0) delete r[emoji];
  if (Object.keys(r).length === 0) {
    chatReactions.delete(key);
    const s = reactionsByChat.get(chatKey);
    if (s) { s.delete(mid); if (s.size === 0) reactionsByChat.delete(chatKey); }
  } else {
    if (!reactionsByChat.has(chatKey)) reactionsByChat.set(chatKey, new Set());
    reactionsByChat.get(chatKey).add(mid);
  }
  res.json({ ok: true });
});

app.get('/chat/:chatKey/reactions', (req, res) => {
  const chatKey = req.params.chatKey;
  const idx = reactionsByChat.get(chatKey);
  const result = {};
  if (idx) {
    for (const mid of idx) {
      const v = chatReactions.get(`${chatKey}_${mid}`);
      if (v && Object.keys(v).length > 0) result[mid] = v;
    }
  }
  res.json(result);
});

// --- Read receipts ---
app.post('/chat/:chatKey/read', (req, res) => {
  const { fipId, actor } = req.body;
  if (!isNonEmptyString(fipId, 128)) return res.sendStatus(400);
  if (actor !== fipId) return res.sendStatus(403);
  const key = req.params.chatKey;
  if (!chatHasParticipant(key, fipId)) return res.sendStatus(403);
  if (!chatReads.has(key)) chatReads.set(key, {});
  chatReads.get(key)[fipId] = Date.now();
  res.sendStatus(200);
});

app.get('/chat/:chatKey/read', (req, res) => {
  res.json(chatReads.get(req.params.chatKey) || {});
});

// --- Typing indicator ---
app.post('/typing/:chatKey', (req, res) => {
  const { fipId, ts, actor } = req.body;
  if (!isNonEmptyString(fipId, 128)) return res.sendStatus(400);
  if (actor !== fipId) return res.sendStatus(403);
  const key = req.params.chatKey;
  if (!chatHasParticipant(key, fipId)) return res.sendStatus(403);
  if (!typingMap.has(key)) {
    if (typingMap.size >= MAX_TYPING_KEYS) {
      // evict oldest key
      const first = typingMap.keys().next().value;
      if (first !== undefined) typingMap.delete(first);
    }
    typingMap.set(key, []);
  }
  const list = typingMap.get(key);
  const idx = list.findIndex(t => t.fipId === fipId);
  const entry = { fipId, ts: ts || Date.now() };
  if (idx === -1) list.push(entry);
  else list[idx] = entry;
  res.sendStatus(200);
});

app.get('/typing/:chatKey', (req, res) => {
  const now = Date.now();
  const list = typingMap.get(req.params.chatKey) || [];
  res.json(list.filter(t => now - t.ts < 4000));
});

// --- Deactivate ---
app.post('/deactivate', (req, res) => {
  const { fipId, actor } = req.body;
  if (!isNonEmptyString(fipId, 128)) return res.sendStatus(400);
  if (actor !== fipId) return res.sendStatus(403);
  const prev = users.get(fipId);
  if (prev && prev.code) codeToFipId.delete(prev.code);
  users.delete(fipId);
  requests.delete(fipId);
  accepted.delete(fipId);
  [...chats.keys()].filter(k => chatHasParticipant(k, fipId)).forEach(k => {
    chats.delete(k);
    const idx = reactionsByChat.get(k);
    if (idx) {
      for (const mid of idx) chatReactions.delete(`${k}_${mid}`);
      reactionsByChat.delete(k);
    }
    chatReads.delete(k);
  });
  [...typingMap.keys()].filter(k => chatHasParticipant(k, fipId)).forEach(k => typingMap.delete(k));
  stories.delete(fipId);
  userNotifs.delete(fipId);
  for (const [, g] of groups) {
    g.members = g.members.filter(m => m.fipId !== fipId);
    g.joinRequests = g.joinRequests.filter(r => r.fromFipId !== fipId);
  }
  res.sendStatus(200);
});

// --- Bridge registry ---
// Entries are {serverUrl, owner}. `owner` is the fipId that first claimed the
// code; only that fipId may point it somewhere else afterwards. Without this
// anyone could repoint another user's code at their own server and intercept
// friend requests. Legacy entries are bare strings (no owner) and stay claimable.
function registryUrlOf(entry) {
  if (!entry) return null;
  return typeof entry === 'string' ? entry : entry.serverUrl;
}
function registryOwnerOf(entry) {
  return entry && typeof entry === 'object' ? entry.owner || null : null;
}

app.post('/registry/register', (req, res) => {
  const { code, serverUrl, actor } = req.body;
  if (!isNonEmptyString(code, 32) || !isNonEmptyString(serverUrl, 500)) return res.sendStatus(400);
  const prev = registry.get(code);
  const owner = registryOwnerOf(prev);
  if (owner && owner !== actor) return res.status(403).json({ error: 'code claimed by another user' });
  if (registry.size >= MAX_REGISTRY && !registry.has(code)) return res.status(429).json({ error: 'registry full' });
  registry.set(code, { serverUrl, owner: owner || (typeof actor === 'string' ? actor : null) });
  res.sendStatus(200);
});

app.get('/registry/lookup/:code', (req, res) => {
  const serverUrl = registryUrlOf(registry.get(req.params.code));
  if (!serverUrl) return res.sendStatus(404);
  res.json({ serverUrl });
});

// --- Paid tiers (bridge role) ---
const TIER_NAMES = [
  'vip', 'vipPlus', 'pvip', 'pvipPlus',
  'photon', 'photonPlus', 'photonPulse', 'photonPulseVip',
];

// Subscriptions lapse by timestamp rather than by a scheduled sweep: expiry is
// evaluated on every read, so a stale record simply stops counting.
function readTier(fipId) {
  const t = tiers.get(fipId);
  if (!t) return null;
  if (t.expiresAt && Date.now() >= t.expiresAt) return null;
  return t;
}

function publicTier(fipId) {
  const t = readTier(fipId);
  if (!t) return { tier: 'none', fakeActive: false, fakeName: '', color: 0, expiresAt: 0 };
  // Fake names are gated here rather than in the client: this response is what
  // every other device trusts, so a client that lies about its tier cannot make
  // peers render an alias it has not paid for.
  const mayAlias = t.tier === 'photonPulseVip';
  return {
    tier: t.tier,
    color: t.color || 0,
    fakeName: mayAlias ? (t.fakeName || '') : '',
    fakeActive: mayAlias && !!t.fakeActive && !!(t.fakeName || '').trim(),
    expiresAt: t.expiresAt || 0,
  };
}

// Grants a subscription. Deliberately unauthenticated for now: it is the manual
// test path while Play Billing is not wired up, and the shop UI never calls it.
// Receipt verification against the Play Developer API belongs here.
app.post('/tier/grant', medBody, (req, res) => {
  const { fipId, tier, months } = req.body;
  if (!isNonEmptyString(fipId, 128)) return res.sendStatus(400);
  // 'none' revokes, so the unsubscribed state can be exercised without waiting
  // a month for the expiry to land.
  if (tier === 'none') {
    tiers.delete(fipId);
    return res.json({ ok: true, ...publicTier(fipId) });
  }
  if (!TIER_NAMES.includes(tier)) return res.status(400).json({ error: 'unknown tier' });
  const m = Number.isFinite(months) && months > 0 ? Math.min(months, 24) : 1;
  const prev = tiers.get(fipId) || {};
  tiers.set(fipId, {
    ...prev,
    tier,
    expiresAt: Date.now() + m * 30 * 24 * 60 * 60 * 1000,
  });
  res.json({ ok: true, ...publicTier(fipId) });
});

app.get('/tier/:fipId', (req, res) => {
  res.json(publicTier(req.params.fipId));
});

// Colour and fake-name preferences. Only the owner may change their own.
app.post('/tier/:fipId/prefs', medBody, (req, res) => {
  const fipId = req.params.fipId;
  const { color, fakeName, fakeActive, actor } = req.body;
  if (actor !== fipId) return res.sendStatus(403);
  const current = readTier(fipId);
  if (!current) return res.status(403).json({ error: 'no active subscription' });
  if (color !== undefined && !Number.isInteger(color)) return res.sendStatus(400);
  if (fakeName !== undefined && (typeof fakeName !== 'string' || fakeName.length > 100)) {
    return res.sendStatus(400);
  }
  const next = { ...current };
  if (color !== undefined) next.color = color;
  if (fakeName !== undefined) next.fakeName = fakeName;
  if (fakeActive !== undefined) next.fakeActive = !!fakeActive;
  tiers.set(fipId, next);
  res.json({ ok: true, ...publicTier(fipId) });
});

// One request for a whole contact list or member roster — rendering N badges
// must not cost N round-trips.
app.post('/tiers/batch', medBody, (req, res) => {
  const { fipIds } = req.body;
  if (!Array.isArray(fipIds)) return res.sendStatus(400);
  const out = {};
  for (const id of fipIds.slice(0, 500)) {
    if (typeof id === 'string' && id) out[id] = publicTier(id);
  }
  res.json(out);
});

// --- Groups ---
app.post('/groups', (req, res) => {
  const { ownerFipId, ownerName, name, ownerServerUrl, description, actor } = req.body;
  if (!isNonEmptyString(ownerFipId, 128) || !isNonEmptyString(name, 100)) return res.sendStatus(400);
  if (actor !== ownerFipId) return res.sendStatus(403);
  const groupId = `grp_${Date.now()}_${Math.random().toString(36).slice(2)}`;
  const groupCode = rand(7);
  groups.set(groupId, {
    groupId, groupCode,
    name: name.slice(0, 100),
    // The client sends this on create and reads it back when joining by code.
    // It used to be dropped here, so every joiner saw an empty description.
    description: typeof description === 'string' ? description.slice(0, 120) : '',
    ownerFipId,
    ownerName: typeof ownerName === 'string' ? ownerName.slice(0, 100) : '',
    ownerServerUrl: typeof ownerServerUrl === 'string' ? ownerServerUrl.slice(0, 500) : '',
    members: [{ fipId: ownerFipId, name: ownerName, serverUrl: ownerServerUrl }],
    joinRequests: [], messages: [],
    muted: [],
    groupKeys: {},
  });
  groupCodeIndex.set(groupCode, groupId);
  res.json({ groupId, groupCode, name, description: groups.get(groupId).description, ownerFipId, ownerServerUrl });
});

app.get('/groups/by-code/:code', (req, res) => {
  const groupId = groupCodeIndex.get(req.params.code);
  if (groupId) {
    const g = groups.get(groupId);
    if (g) return res.json({ groupId: g.groupId, groupCode: g.groupCode, name: g.name, description: g.description || '', ownerFipId: g.ownerFipId, ownerServerUrl: g.ownerServerUrl });
  }
  res.sendStatus(404);
});

app.post('/groups/:groupId/join-requests', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  const { fromFipId, fromName, fromServerUrl, actor } = req.body;
  if (!isNonEmptyString(fromFipId, 128)) return res.sendStatus(400);
  if (actor !== fromFipId) return res.sendStatus(403);
  if (g.joinRequests.length >= MAX_JOIN_REQUESTS) return res.status(429).json({ error: 'too many join requests' });
  if (!g.joinRequests.find(r => r.fromFipId === fromFipId))
    g.joinRequests.push({
      fromFipId,
      fromName: typeof fromName === 'string' ? fromName.slice(0, 100) : '',
      fromServerUrl: typeof fromServerUrl === 'string' ? fromServerUrl.slice(0, 500) : '',
      ts: Date.now(),
    });
  res.sendStatus(200);
});

app.get('/groups/:groupId/join-requests', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  res.json(g.joinRequests);
});

app.delete('/groups/:groupId/join-requests/:fipId', medBody, (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  const actor = req.body && req.body.actor;
  if (actor !== g.ownerFipId && actor !== req.params.fipId) return res.sendStatus(403);
  g.joinRequests = g.joinRequests.filter(r => r.fromFipId !== req.params.fipId);
  res.sendStatus(200);
});

app.get('/groups/:groupId/members', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  res.json({ members: g.members });
});

app.post('/groups/:groupId/members', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  const { fipId, name, serverUrl, actor } = req.body;
  if (!isNonEmptyString(fipId, 128)) return res.sendStatus(400);
  // Allow either: owner adds anyone, or the joiner adds themselves IF they have an approved joinRequest.
  const hasPendingReq = !!g.joinRequests.find(r => r.fromFipId === fipId);
  if (actor === g.ownerFipId) {
    // owner may add anyone
  } else if (actor === fipId && hasPendingReq) {
    // self-join only after owner approved via join-request flow; conservative: still require pending req present
  } else {
    return res.sendStatus(403);
  }
  if (!g.members.find(m => m.fipId === fipId)) {
    g.members.push({
      fipId,
      name: typeof name === 'string' ? name.slice(0, 100) : '',
      serverUrl: typeof serverUrl === 'string' ? serverUrl.slice(0, 500) : '',
    });
  }
  g.joinRequests = g.joinRequests.filter(r => r.fromFipId !== fipId);
  res.sendStatus(200);
});

app.delete('/groups/:groupId/members/:fipId', medBody, (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  const actor = req.body && req.body.actor;
  if (actor !== g.ownerFipId && actor !== req.params.fipId) return res.sendStatus(403);
  // Owner cannot be kicked.
  if (req.params.fipId === g.ownerFipId && actor !== g.ownerFipId) return res.sendStatus(403);
  g.members = g.members.filter(m => m.fipId !== req.params.fipId);
  g.muted = (g.muted || []).filter(id => id !== req.params.fipId);
  res.sendStatus(200);
});

app.post('/groups/:groupId/muted', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  if (!requireOwner(req, res, g)) return;
  const { fipId } = req.body;
  if (!isNonEmptyString(fipId, 128)) return res.sendStatus(400);
  if (!g.muted) g.muted = [];
  if (!g.muted.includes(fipId)) g.muted.push(fipId);
  res.sendStatus(200);
});

app.delete('/groups/:groupId/muted/:fipId', medBody, (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  if (!requireOwner(req, res, g)) return;
  if (!g.muted) g.muted = [];
  g.muted = g.muted.filter(id => id !== req.params.fipId);
  res.sendStatus(200);
});

app.get('/groups/:groupId/muted', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  res.json(g.muted || []);
});

app.post('/groups/:groupId/messages', bigBody, (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  const { from, fromName, text, ts, type, question, options, actor } = req.body;
  if (!isNonEmptyString(from, 128)) return res.sendStatus(400);
  if (actor !== from) return res.sendStatus(403);
  if (!isMember(g, from)) return res.status(403).json({ error: 'Grup üyesi değilsiniz.' });
  if ((g.muted || []).includes(from)) return res.status(403).json({ error: 'Susturuldunuz.' });
  const uniqueSenders = [...new Set(g.messages.map(m => m.from))];
  if (!uniqueSenders.includes(from) && uniqueSenders.length >= 10)
    return res.status(429).json({ error: 'Slot limit reached (10 senders max)' });
  const id = msgId();
  if (type === 'poll') {
    if (!isNonEmptyString(question, 500)) return res.sendStatus(400);
    if (!Array.isArray(options) || options.length < 2 || options.length > 10) return res.sendStatus(400);
    const cleanOpts = options.slice(0, 10).map(o => typeof o === 'string' ? o.slice(0, 200) : String(o).slice(0, 200));
    // Ignore client-supplied `votes` on create — always start empty.
    g.messages.push({ from, fromName, type, question: question.slice(0, 500), options: cleanOpts, votes: {}, ts: ts || Date.now(), msgId: id });
  } else {
    if (typeof text === 'string' && text.length > 8000) return res.status(413).json({ error: 'text too long' });
    g.messages.push({ from, fromName, text: typeof text === 'string' ? text : '', ts: ts || Date.now(), msgId: id });
  }
  if (g.messages.length > 500) g.messages.splice(0, g.messages.length - 500);
  res.json({ msgId: id });
});

app.get('/groups/:groupId/messages', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  res.json(g.messages);
});

app.post('/groups/:groupId/messages/:msgId/vote', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.status(404).json({ error: 'Grup bulunamadı' });
  const { fipId, optionIndex, actor } = req.body;
  if (!isNonEmptyString(fipId, 128) || !Number.isInteger(optionIndex)) return res.sendStatus(400);
  if (actor !== fipId) return res.sendStatus(403);
  if (!isMember(g, fipId)) return res.status(403).json({ error: 'Grup üyesi değilsiniz.' });
  const msg = (g.messages || []).find(m => m.msgId === req.params.msgId);
  if (!msg) return res.status(404).json({ error: 'Mesaj bulunamadı' });
  if (msg.type !== 'poll') return res.status(400).json({ error: 'Anket değil' });
  if (optionIndex < 0 || optionIndex >= (msg.options || []).length) return res.status(400).json({ error: 'Geçersiz seçenek' });
  if (!msg.votes) msg.votes = {};
  msg.votes[fipId] = optionIndex;
  res.json({ ok: true });
});

// --- Group announcements ---
app.post('/groups/:groupId/announce', medBody, (req, res) => {
  const { from, fromName, text, actor } = req.body;
  const g = groups.get(req.params.groupId);
  if (!g) return res.status(404).json({ error: 'Grup bulunamadı' });
  if (actor !== from) return res.sendStatus(403);
  if (g.ownerFipId !== from) return res.status(403).json({ error: 'Sadece sahip duyuru yapabilir' });
  if (!isNonEmptyString(text, 4000)) return res.sendStatus(400);
  const ann = { id: msgId(), from, fromName, text: text.slice(0, 4000), ts: Date.now() };
  if (!groupAnnouncements.has(req.params.groupId)) groupAnnouncements.set(req.params.groupId, []);
  const list = groupAnnouncements.get(req.params.groupId);
  list.push(ann);
  if (list.length > 100) list.splice(0, list.length - 100);
  res.json({ ok: true, id: ann.id });
});

app.get('/groups/:groupId/announcements', (req, res) => {
  res.json(groupAnnouncements.get(req.params.groupId) || []);
});

app.post('/groups/:groupId/key/:memberFipId', bigBody, (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  const { encryptedKey, actor } = req.body;
  // Only the owner may publish per-member group keys.
  if (actor !== g.ownerFipId) return res.sendStatus(403);
  if (typeof encryptedKey !== 'string' || encryptedKey.length > 50_000_000) return res.sendStatus(400);
  if (!g.groupKeys) g.groupKeys = {};
  g.groupKeys[req.params.memberFipId] = encryptedKey;
  res.sendStatus(200);
});

app.get('/groups/:groupId/key/:memberFipId', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  const key = (g.groupKeys || {})[req.params.memberFipId];
  if (!key) return res.sendStatus(404);
  res.json({ encryptedKey: key });
});

// --- Pulse AI ---
app.post('/ai/chat', aiLimiter, medBody, async (req, res) => {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return res.status(503).json({ error: 'Pulse AI henüz yapılandırılmadı.' });

  const { messages } = req.body;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > 40)
    return res.status(400).json({ error: 'Mesaj listesi gerekli.' });
  for (const m of messages) {
    if (!m || typeof m !== 'object') return res.status(400).json({ error: 'Geçersiz mesaj.' });
    if (m.role !== 'user' && m.role !== 'assistant') return res.status(400).json({ error: 'Geçersiz rol.' });
    if (typeof m.content !== 'string' || m.content.length > 8000) return res.status(400).json({ error: 'Geçersiz içerik.' });
  }

  try {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-api-key': apiKey, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 1024,
        system: 'Sen Pulse AI\'sin — Photon Chat uygulamasının kişisel yapay zeka asistanısın. Kullanıcıya Türkçe yardım et. Kelime anlamları, genel sorular, sohbet — her konuda kısa ve samimi cevaplar ver. Asla görsel, dosya veya bağlantı paylaşma.',
        messages,
      }),
    });
    if (!response.ok) return res.status(502).json({ error: 'AI yanıt vermedi.' });
    const data = await response.json();
    const reply = data && data.content && data.content[0] && data.content[0].text;
    if (!reply) return res.status(502).json({ error: 'AI yanıt vermedi.' });
    res.json({ reply });
  } catch (e) {
    res.status(502).json({ error: 'AI bağlantı hatası.' });
  }
});

// --- Notifications ---
// Only someone the recipient has accepted may push a notification to them.
// This endpoint was previously unauthenticated, so anyone who knew a fipId
// could spam that user's notification tray. The auto-notify on POST /chat runs
// in-process and does not go through here, so it is unaffected.
app.post('/notifs/:fipId', (req, res) => {
  const { title, body, ts, actor } = req.body;
  if (!isNonEmptyString(title, 200) || !isNonEmptyString(body, 1000)) return res.sendStatus(400);
  if (!isNonEmptyString(actor, 128)) return res.sendStatus(403);
  const targetAccepted = accepted.get(req.params.fipId);
  if (!targetAccepted || !targetAccepted.has(actor)) return res.sendStatus(403);
  if (!userNotifs.has(req.params.fipId)) userNotifs.set(req.params.fipId, []);
  const list = userNotifs.get(req.params.fipId);
  const notifTs = ts || Date.now();
  if (list.some(n => n.ts === notifTs && n.title === title && n.body === body)) return res.status(409).json({ error: 'duplicate' });
  list.push({ title: title.slice(0, 200), body: body.slice(0, 1000), ts: notifTs });
  if (list.length > 50) list.splice(0, list.length - 50);
  res.sendStatus(200);
});

app.delete('/notifs/:fipId/:ts', (req, res) => {
  const list = userNotifs.get(req.params.fipId);
  if (!list) return res.sendStatus(404);
  const ts = Number(req.params.ts);
  if (!Number.isFinite(ts)) return res.sendStatus(400);
  const next = list.filter(n => n.ts !== ts);
  if (next.length === list.length) return res.sendStatus(404);
  userNotifs.set(req.params.fipId, next);
  res.sendStatus(200);
});

app.get('/notifs/:fipId', (req, res) => {
  const list = userNotifs.get(req.params.fipId) || [];
  const now = Date.now();
  const fresh = list.filter(n => (n.ts || 0) > now - 10 * 60 * 1000);
  if (fresh.length !== list.length) userNotifs.set(req.params.fipId, fresh);
  res.json(fresh);
});

// --- Stories ---
app.post('/stories/:fipId', bigBody, (req, res) => {
  const { actor } = req.body;
  if (actor !== req.params.fipId) return res.sendStatus(403);
  const list = stories.get(req.params.fipId) || [];
  const now = Date.now();
  const filtered = list.filter(s => (s.expiresAt || 0) > now);
  if (filtered.length >= MAX_STORIES_PER_USER) filtered.splice(0, filtered.length - (MAX_STORIES_PER_USER - 1));
  // Whitelist known fields, drop actor. Client sends `type`/`content`/`authorFipId`/`authorName`/`bgColor`.
  const { id, type, content, authorFipId, authorName, bgColor, mediaType, media, caption, expiresAt, ts } = req.body;
  const item = {
    id: id || msgId(),
    type, content, authorFipId, authorName, bgColor,
    mediaType, media, caption,
    expiresAt: expiresAt || (now + 24 * 60 * 60 * 1000),
    ts: ts || now,
  };
  filtered.push(item);
  stories.set(req.params.fipId, filtered);
  res.json({ id: item.id });
});
app.get('/stories/:fipId', (req, res) => {
  const list = stories.get(req.params.fipId) || [];
  const now = Date.now();
  res.json(list.filter(s => (s.expiresAt || 0) > now));
});
app.delete('/stories/:fipId/:storyId', medBody, (req, res) => {
  const actor = req.body && req.body.actor;
  if (actor !== req.params.fipId) return res.sendStatus(403);
  const list = stories.get(req.params.fipId) || [];
  const next = list.filter(s => s.id !== req.params.storyId);
  if (next.length === list.length) return res.sendStatus(404);
  stories.set(req.params.fipId, next);
  res.sendStatus(200);
});

// --- Device Link ---
app.post('/device-link/:ownerFipId', medBody, (req, res) => {
  const { requesterFipId } = req.body;
  if (!isNonEmptyString(requesterFipId, 128)) return res.sendStatus(400);
  const banned = deviceBans.get(req.params.ownerFipId) || new Set();
  if (banned.has(requesterFipId)) return res.status(403).json({ error: 'banned' });
  const list = deviceLinkRequests.get(req.params.ownerFipId) || [];
  if (list.length >= 50) return res.status(429).json({ error: 'too many pending' });
  // Whitelist fields.
  const { requesterName, requesterServerUrl } = req.body;
  if (!list.find(r => r.requesterFipId === requesterFipId)) {
    list.push({
      requesterFipId,
      requesterName: typeof requesterName === 'string' ? requesterName.slice(0, 100) : '',
      requesterServerUrl: typeof requesterServerUrl === 'string' ? requesterServerUrl.slice(0, 500) : '',
      status: 'pending', attempts: 0, ts: Date.now(),
    });
  }
  deviceLinkRequests.set(req.params.ownerFipId, list);
  deviceLinkStatus.set(requesterFipId, { status: 'pending' });
  res.sendStatus(200);
});
app.get('/device-link/:fipId', (req, res) => {
  res.json(deviceLinkRequests.get(req.params.fipId) || []);
});
app.post('/device-link/:ownerFipId/respond', medBody, (req, res) => {
  const { requesterFipId, status, code, actor } = req.body;
  if (actor !== req.params.ownerFipId) return res.sendStatus(403);
  if (!isNonEmptyString(requesterFipId, 128) || !isNonEmptyString(status, 32)) return res.sendStatus(400);
  // `code` is optional (reject/kick send none) but must stay short when present
  // — it is retained in memory per pending request.
  if (code !== undefined && code !== null && (typeof code !== 'string' || code.length > 64)) {
    return res.sendStatus(400);
  }
  const list = deviceLinkRequests.get(req.params.ownerFipId) || [];
  const idx = list.findIndex(r => r.requesterFipId === requesterFipId);
  if (idx !== -1) {
    if (status === 'reject') {
      list.splice(idx, 1);
    } else {
      list[idx].status = status;
      list[idx].code = code;
    }
    deviceLinkRequests.set(req.params.ownerFipId, list);
  }
  deviceLinkStatus.set(requesterFipId, { status, code });
  res.sendStatus(200);
});
app.get('/device-link-status/:requesterFipId', (req, res) => {
  const st = deviceLinkStatus.get(req.params.requesterFipId);
  if (!st) return res.sendStatus(404);
  res.json(st);
});
app.post('/device-link/:ownerFipId/verify', medBody, (req, res) => {
  const { requesterFipId, code, actor } = req.body;
  if (actor !== requesterFipId) return res.sendStatus(403);
  if (!isNonEmptyString(requesterFipId, 128) || !isNonEmptyString(code, 32)) return res.sendStatus(400);
  const list = deviceLinkRequests.get(req.params.ownerFipId) || [];
  const idx = list.findIndex(r => r.requesterFipId === requesterFipId);
  if (idx === -1) return res.status(404).json({ error: 'not-found' });
  list[idx].attempts = (list[idx].attempts || 0) + 1;
  const attempts = list[idx].attempts;
  const ok = list[idx].code === code;
  if (ok) {
    deviceLinkStatus.set(requesterFipId, { status: 'linked' });
    const linkedDeviceId = (typeof req.body.deviceId === 'string' && req.body.deviceId) || `${req.params.ownerFipId}_${requesterFipId}`;
    deviceIdToRequester.set(linkedDeviceId, requesterFipId);
    list.splice(idx, 1);
  } else if (attempts >= 3) {
    deviceLinkStatus.set(requesterFipId, { status: 'fake' });
    if (!deviceBans.has(req.params.ownerFipId)) deviceBans.set(req.params.ownerFipId, new Set());
    deviceBans.get(req.params.ownerFipId).add(requesterFipId);
    list.splice(idx, 1);
  } else {
    deviceLinkStatus.set(requesterFipId, { status: 'retry', attempt: attempts });
  }
  deviceLinkRequests.set(req.params.ownerFipId, list);
  res.json({ ok, attempts });
});
app.delete('/device-link/:ownerFipId/:deviceId', medBody, (req, res) => {
  const actor = req.body && req.body.actor;
  if (actor !== req.params.ownerFipId) return res.sendStatus(403);
  deviceActivities.delete(`${req.params.ownerFipId}_${req.params.deviceId}`);
  const requesterFipId = deviceIdToRequester.get(req.params.deviceId);
  if (requesterFipId) {
    deviceLinkStatus.set(requesterFipId, { status: 'kicked' });
    deviceIdToRequester.delete(req.params.deviceId);
  }
  res.sendStatus(200);
});

app.post('/device-activity/:ownerFipId', medBody, (req, res) => {
  const { deviceId, actor } = req.body;
  if (!isNonEmptyString(deviceId, 128)) return res.sendStatus(400);
  // Either the owner (self-report) or a linked device may append its own activity.
  const linkedOwner = deviceIdToRequester.get(deviceId);
  if (actor !== req.params.ownerFipId && actor !== linkedOwner) return res.sendStatus(403);
  const key = `${req.params.ownerFipId}_${deviceId}`;
  const list = deviceActivities.get(key) || [];
  const { action, detail, ts } = req.body;
  list.push({ deviceId, action, detail, ts: ts || Date.now() });
  if (list.length > 500) list.splice(0, list.length - 500);
  deviceActivities.set(key, list);
  res.sendStatus(200);
});
app.get('/device-activity/:ownerFipId/:deviceId', (req, res) => {
  const key = `${req.params.ownerFipId}_${req.params.deviceId}`;
  res.json(deviceActivities.get(key) || []);
});

app.post('/device-ban/:ownerFipId', medBody, (req, res) => {
  const { bannedFipId, actor } = req.body;
  if (actor !== req.params.ownerFipId) return res.sendStatus(403);
  if (!isNonEmptyString(bannedFipId, 128)) return res.sendStatus(400);
  if (!deviceBans.has(req.params.ownerFipId)) deviceBans.set(req.params.ownerFipId, new Set());
  deviceBans.get(req.params.ownerFipId).add(bannedFipId);
  res.sendStatus(200);
});
app.get('/device-ban/:ownerFipId', (req, res) => {
  res.json([...(deviceBans.get(req.params.ownerFipId) || new Set())]);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Photon Chat server running on port ${PORT}`));
