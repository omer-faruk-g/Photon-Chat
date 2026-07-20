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
app.use(express.json({ limit: '256kb' }));
// Larger body limit for endpoints that carry base64 media (avatars, images, files, stories, group keys).
const bigBody = express.json({ limit: '60mb' });

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
const chatReads = new Map(); // chatKey -> { fipId: ts }
const chatReactions = new Map(); // `${chatKey}_${msgId}` -> {emoji: [fipId,...]}
const userNotifs = new Map();
const groupAnnouncements = new Map(); // groupId -> [{id, from, fromName, text, ts}]
const stories = new Map(); // fipId -> [{id, ...storyData, ts, expiresAt}]
const deviceLinkRequests = new Map(); // ownerFipId -> [{requesterFipId, requesterName, ts, status, code}]
const deviceLinkStatus = new Map(); // requesterFipId -> {status, code, ...}
const deviceActivities = new Map(); // ownerFipId -> [{deviceId, action, detail, ts}]
const deviceBans = new Map(); // ownerFipId -> Set<bannedFipId>
const codeToFipId = new Map(); // code -> fipId (O(1) lookup)
const groupCodeIndex = new Map(); // groupCode -> groupId (O(1) lookup)
const deviceIdToRequester = new Map(); // deviceId -> requesterFipId (populated on successful verify)

// --- Auth helpers ---
function requireOwner(req, res, group) {
  if (req.body.actor !== group.ownerFipId) { res.sendStatus(403); return false; }
  return true;
}
function requireMessageAuthor(req, res, msg) {
  if (req.body.actor !== msg.from) { res.sendStatus(403); return false; }
  return true;
}

// --- Persistence ---
const SNAPSHOT_FILE = process.env.SNAPSHOT_FILE || '/tmp/photon-snapshot.json';

function mapToObj(m) {
  const o = {};
  for (const [k, v] of m) o[k] = v instanceof Set ? [...v] : v;
  return o;
}
function objToMap(o, asSet = false) {
  const m = new Map();
  for (const k of Object.keys(o || {})) m.set(k, asSet ? new Set(o[k]) : o[k]);
  return m;
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
    for (const [k, v] of Object.entries(raw.chatReads || {})) chatReads.set(k, v);
    for (const [k, v] of Object.entries(raw.chatReactions || {})) chatReactions.set(k, v);
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
      chatReads: mapToObj(chatReads),
      chatReactions: mapToObj(chatReactions),
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

function rand(n) {
  return Math.floor(Math.random() * Math.pow(10, n)).toString().padStart(n, '0');
}

function msgId() {
  return `${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
}

// --- Presence ---
app.post('/presence', bigBody, (req, res) => {
  const { fipId, code, name, publicKey, serverUrl, statusMsg, avatar, bio } = req.body;
  if (!fipId) return res.sendStatus(400);
  if (avatar && typeof avatar === 'string' && avatar.length > 300_000) {
    return res.status(413).json({ error: 'avatar too large' });
  }
  // Maintain reverse index
  const prev = users.get(fipId);
  if (prev && prev.code && prev.code !== code) codeToFipId.delete(prev.code);
  users.set(fipId, { code, name, publicKey, serverUrl, statusMsg: statusMsg || '', avatar: avatar || '', bio: bio || '', lastSeen: Date.now() });
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
app.post('/requests/:toFipId', bigBody, (req, res) => {
  const { toFipId } = req.params;
  const { fromFipId, fromCode, fromName, fromServerUrl, fromPublicKey, bio } = req.body;
  if (!requests.has(toFipId)) requests.set(toFipId, []);
  const list = requests.get(toFipId);
  if (!list.find(r => r.fromFipId === fromFipId)) {
    list.push({ fromFipId, fromCode, fromName, fromServerUrl, fromPublicKey, bio: bio || '', ts: Date.now() });
  }
  res.sendStatus(200);
});

app.get('/requests/:toFipId', (req, res) => {
  res.json(requests.get(req.params.toFipId) || []);
});

app.post('/accept', (req, res) => {
  const { myFipId, otherFipId } = req.body;
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
  res.json((fipIds || []).filter(id => users.has(id)));
});

// --- Direct messages ---
app.get('/chat/:chatKey', (req, res) => {
  res.json(chats.get(req.params.chatKey) || []);
});

app.post('/chat/:chatKey', bigBody, (req, res) => {
  const key = req.params.chatKey;
  if (typeof req.body.text === 'string' && req.body.text.length > 8000) {
    return res.status(413).json({ error: 'text too long' });
  }
  if (!chats.has(key)) chats.set(key, []);
  const msgs = chats.get(key);
  const id = msgId();
  msgs.push({ ...req.body, msgId: id });
  if (msgs.length > 200) msgs.splice(0, msgs.length - 200);
  // Auto-notify recipient
  const { toFipId, fromName } = req.body;
  if (toFipId && fromName) {
    if (!userNotifs.has(toFipId)) userNotifs.set(toFipId, []);
    userNotifs.get(toFipId).push({ title: 'Yeni mesaj', body: `${fromName} size mesaj attı`, ts: Date.now() });
  }
  res.json({ msgId: id });
});

app.delete('/chat/:chatKey', (req, res) => {
  chats.delete(req.params.chatKey);
  res.sendStatus(200);
});

app.delete('/chat/:chatKey/msg/:msgId', express.json(), (req, res) => {
  const msgs = chats.get(req.params.chatKey);
  if (!msgs) return res.sendStatus(404);
  const idx = msgs.findIndex(m => m.msgId === req.params.msgId);
  if (idx === -1) return res.sendStatus(404);
  if (!requireMessageAuthor(req, res, msgs[idx])) return;
  msgs[idx] = { ...msgs[idx], text: '', deleted: true };
  res.sendStatus(200);
});

app.put('/chat/:chatKey/msg/:msgId', (req, res) => {
  const msgs = chats.get(req.params.chatKey);
  if (!msgs) return res.sendStatus(404);
  const idx = msgs.findIndex(m => m.msgId === req.params.msgId);
  if (idx === -1) return res.sendStatus(404);
  if (!requireMessageAuthor(req, res, msgs[idx])) return;
  msgs[idx] = { ...msgs[idx], text: req.body.text, edited: true };
  res.sendStatus(200);
});

// --- Reactions ---
app.post('/chat/:chatKey/msg/:msgId/react', (req, res) => {
  const key = `${req.params.chatKey}_${req.params.msgId}`;
  const { fipId, emoji } = req.body;
  if (!chatReactions.has(key)) chatReactions.set(key, {});
  const r = chatReactions.get(key);
  if (!r[emoji]) r[emoji] = [];
  const idx = r[emoji].indexOf(fipId);
  if (idx === -1) r[emoji].push(fipId); else r[emoji].splice(idx, 1);
  if (r[emoji].length === 0) delete r[emoji];
  res.json({ ok: true });
});

app.get('/chat/:chatKey/reactions', (req, res) => {
  const result = {};
  for (const [k, v] of chatReactions) {
    if (k.startsWith(req.params.chatKey + '_')) {
      const msgId2 = k.slice(req.params.chatKey.length + 1);
      if (Object.keys(v).length > 0) result[msgId2] = v;
    }
  }
  res.json(result);
});

// --- Read receipts ---
app.post('/chat/:chatKey/read', (req, res) => {
  const { fipId } = req.body;
  if (!fipId) return res.sendStatus(400);
  const key = req.params.chatKey;
  if (!chatReads.has(key)) chatReads.set(key, {});
  chatReads.get(key)[fipId] = Date.now();
  res.sendStatus(200);
});

app.get('/chat/:chatKey/read', (req, res) => {
  res.json(chatReads.get(req.params.chatKey) || {});
});

// --- Typing indicator ---
app.post('/typing/:chatKey', (req, res) => {
  const { fipId, ts } = req.body;
  if (!fipId) return res.sendStatus(400);
  const key = req.params.chatKey;
  if (!typingMap.has(key)) typingMap.set(key, []);
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
  const { fipId } = req.body;
  const prev = users.get(fipId);
  if (prev && prev.code) codeToFipId.delete(prev.code);
  users.delete(fipId);
  requests.delete(fipId);
  accepted.delete(fipId);
  // Collect keys first — never mutate a Map while iterating it.
  [...chats.keys()].filter(k => k.split('_').includes(fipId)).forEach(k => chats.delete(k));
  [...typingMap.keys()].filter(k => k.split('_').includes(fipId)).forEach(k => typingMap.delete(k));
  for (const [, g] of groups) {
    g.members = g.members.filter(m => m.fipId !== fipId);
    g.joinRequests = g.joinRequests.filter(r => r.fromFipId !== fipId);
  }
  res.sendStatus(200);
});

// --- Bridge registry (global code -> serverUrl directory) ---
app.post('/registry/register', (req, res) => {
  const { code, serverUrl } = req.body;
  if (!code || !serverUrl) return res.sendStatus(400);
  registry.set(code, serverUrl);
  res.sendStatus(200);
});

app.get('/registry/lookup/:code', (req, res) => {
  const serverUrl = registry.get(req.params.code);
  if (!serverUrl) return res.sendStatus(404);
  res.json({ serverUrl });
});

// --- Groups ---
app.post('/groups', (req, res) => {
  const { ownerFipId, ownerName, name, ownerServerUrl } = req.body;
  if (!ownerFipId || !name) return res.sendStatus(400);
  const groupId = `grp_${Date.now()}_${Math.random().toString(36).slice(2)}`;
  const groupCode = rand(7);
  groups.set(groupId, {
    groupId, groupCode, name, ownerFipId, ownerName, ownerServerUrl,
    members: [{ fipId: ownerFipId, name: ownerName, serverUrl: ownerServerUrl }],
    joinRequests: [], messages: [],
    muted: [],
    groupKeys: {},
  });
  groupCodeIndex.set(groupCode, groupId);
  res.json({ groupId, groupCode, name, ownerFipId, ownerServerUrl });
});

app.get('/groups/by-code/:code', (req, res) => {
  const groupId = groupCodeIndex.get(req.params.code);
  if (groupId) {
    const g = groups.get(groupId);
    if (g) return res.json({ groupId: g.groupId, groupCode: g.groupCode, name: g.name, ownerFipId: g.ownerFipId, ownerServerUrl: g.ownerServerUrl });
  }
  res.sendStatus(404);
});

app.post('/groups/:groupId/join-requests', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  const { fromFipId, fromName, fromServerUrl } = req.body;
  if (!g.joinRequests.find(r => r.fromFipId === fromFipId))
    g.joinRequests.push({ fromFipId, fromName, fromServerUrl, ts: Date.now() });
  res.sendStatus(200);
});

app.get('/groups/:groupId/join-requests', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  res.json(g.joinRequests);
});

app.delete('/groups/:groupId/join-requests/:fipId', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
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
  const { fipId, name, serverUrl } = req.body;
  if (!g.members.find(m => m.fipId === fipId)) g.members.push({ fipId, name, serverUrl });
  g.joinRequests = g.joinRequests.filter(r => r.fromFipId !== fipId);
  res.sendStatus(200);
});

app.delete('/groups/:groupId/members/:fipId', express.json(), (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  // Allow either the owner (kick) or the member themselves (leave).
  const actor = req.body && req.body.actor;
  if (actor !== g.ownerFipId && actor !== req.params.fipId) return res.sendStatus(403);
  g.members = g.members.filter(m => m.fipId !== req.params.fipId);
  g.muted = (g.muted || []).filter(id => id !== req.params.fipId);
  res.sendStatus(200);
});

app.post('/groups/:groupId/muted', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  if (!requireOwner(req, res, g)) return;
  const { fipId } = req.body;
  if (!fipId) return res.sendStatus(400);
  if (!g.muted) g.muted = [];
  if (!g.muted.includes(fipId)) g.muted.push(fipId);
  res.sendStatus(200);
});

app.delete('/groups/:groupId/muted/:fipId', express.json(), (req, res) => {
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
  const { from, fromName, text, ts, type, question, options, votes } = req.body;
  if ((g.muted || []).includes(from)) return res.status(403).json({ error: 'Susturuldunuz.' });
  const uniqueSenders = [...new Set(g.messages.map(m => m.from))];
  if (!uniqueSenders.includes(from) && uniqueSenders.length >= 10)
    return res.status(429).json({ error: 'Slot limit reached (10 senders max)' });
  const id = msgId();
  if (type === 'poll') {
    g.messages.push({ from, fromName, type, question, options: options || [], votes: votes || {}, ts: ts || Date.now(), msgId: id });
  } else {
    g.messages.push({ from, fromName, text, ts: ts || Date.now(), msgId: id });
  }
  if (g.messages.length > 500) g.messages.splice(0, g.messages.length - 500);
  res.sendStatus(200);
});

app.get('/groups/:groupId/messages', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  res.json(g.messages);
});

app.post('/groups/:groupId/messages/:msgId/vote', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.status(404).json({ error: 'Grup bulunamadı' });
  const msgs = g.messages || [];
  const msg = msgs.find(m => m.msgId === req.params.msgId);
  if (!msg) return res.status(404).json({ error: 'Mesaj bulunamadı' });
  if (!msg.votes) msg.votes = {};
  msg.votes[req.body.fipId] = req.body.optionIndex;
  res.json({ ok: true });
});

// --- Group announcements ---
app.post('/groups/:groupId/announce', (req, res) => {
  const { from, fromName, text } = req.body;
  const g = groups.get(req.params.groupId);
  if (!g) return res.status(404).json({ error: 'Grup bulunamadı' });
  if (g.ownerFipId !== from) return res.status(403).json({ error: 'Sadece sahip duyuru yapabilir' });
  const ann = { id: msgId(), from, fromName, text, ts: Date.now() };
  if (!groupAnnouncements.has(req.params.groupId)) groupAnnouncements.set(req.params.groupId, []);
  groupAnnouncements.get(req.params.groupId).push(ann);
  res.json({ ok: true, id: ann.id });
});

app.get('/groups/:groupId/announcements', (req, res) => {
  res.json(groupAnnouncements.get(req.params.groupId) || []);
});

app.post('/groups/:groupId/key/:memberFipId', bigBody, (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  const { encryptedKey } = req.body;
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
app.post('/ai/chat', aiLimiter, async (req, res) => {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return res.status(503).json({ error: 'Pulse AI henüz yapılandırılmadı.' });

  const { messages } = req.body;
  if (!Array.isArray(messages) || messages.length === 0)
    return res.status(400).json({ error: 'Mesaj listesi gerekli.' });

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
    const data = await response.json();
    const reply = data.content?.[0]?.text;
    if (!reply) return res.status(502).json({ error: 'AI yanıt vermedi.' });
    res.json({ reply });
  } catch (e) {
    res.status(502).json({ error: 'AI bağlantı hatası.' });
  }
});

// --- Notifications ---
app.post('/notifs/:fipId', (req, res) => {
  const { title, body, ts } = req.body;
  if (!title || !body) return res.sendStatus(400);
  if (!userNotifs.has(req.params.fipId)) userNotifs.set(req.params.fipId, []);
  const list = userNotifs.get(req.params.fipId);
  const notifTs = ts || Date.now();
  // Dedupe by (fipId, ts): reject if a notif with the same ts already exists.
  if (list.some(n => n.ts === notifTs)) return res.status(409).json({ error: 'duplicate' });
  list.push({ title, body, ts: notifTs });
  if (list.length > 50) list.splice(0, list.length - 50);
  res.sendStatus(200);
});

app.delete('/notifs/:fipId/:ts', (req, res) => {
  const list = userNotifs.get(req.params.fipId);
  if (!list) return res.sendStatus(404);
  const ts = Number(req.params.ts);
  userNotifs.set(req.params.fipId, list.filter(n => n.ts !== ts));
  res.sendStatus(200);
});

app.get('/notifs/:fipId', (req, res) => {
  // v7.1: GET is non-destructive so multi-device users don't lose notifs on the first client to poll.
  // Client should call DELETE /notifs/:fipId/:ts after handling.
  const list = userNotifs.get(req.params.fipId) || [];
  // Auto-expire entries older than 10 minutes.
  const now = Date.now();
  const fresh = list.filter(n => (n.ts || 0) > now - 10 * 60 * 1000);
  if (fresh.length !== list.length) userNotifs.set(req.params.fipId, fresh);
  res.json(fresh);
});

// --- Stories (v6.0.0) ---
app.post('/stories/:fipId', bigBody, (req, res) => {
  const list = stories.get(req.params.fipId) || [];
  const item = { ...req.body, id: req.body.id || msgId() };
  // Remove expired before adding
  const now = Date.now();
  const filtered = list.filter(s => (s.expiresAt || 0) > now);
  filtered.push(item);
  stories.set(req.params.fipId, filtered);
  res.sendStatus(200);
});
app.get('/stories/:fipId', (req, res) => {
  const list = stories.get(req.params.fipId) || [];
  const now = Date.now();
  res.json(list.filter(s => (s.expiresAt || 0) > now));
});
app.delete('/stories/:fipId/:storyId', (req, res) => {
  const list = stories.get(req.params.fipId) || [];
  stories.set(req.params.fipId, list.filter(s => s.id !== req.params.storyId));
  res.sendStatus(200);
});

// --- Device Link (v5.0.0) ---
app.post('/device-link/:ownerFipId', (req, res) => {
  // Ban check: reject banned requesters at protocol level
  const banned = deviceBans.get(req.params.ownerFipId) || new Set();
  if (banned.has(req.body.requesterFipId)) return res.status(403).json({ error: 'banned' });
  const list = deviceLinkRequests.get(req.params.ownerFipId) || [];
  list.push({ ...req.body, status: 'pending', attempts: 0 });
  deviceLinkRequests.set(req.params.ownerFipId, list);
  deviceLinkStatus.set(req.body.requesterFipId, { status: 'pending' });
  res.sendStatus(200);
});
app.get('/device-link/:fipId', (req, res) => {
  res.json(deviceLinkRequests.get(req.params.fipId) || []);
});
app.post('/device-link/:ownerFipId/respond', (req, res) => {
  const { requesterFipId, status, code } = req.body;
  // Update pending request
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
  // Publish status for requester to poll
  deviceLinkStatus.set(requesterFipId, { status, code });
  res.sendStatus(200);
});
app.get('/device-link-status/:requesterFipId', (req, res) => {
  const st = deviceLinkStatus.get(req.params.requesterFipId);
  if (!st) return res.sendStatus(404);
  res.json(st);
});
app.post('/device-link/:ownerFipId/verify', (req, res) => {
  const { requesterFipId, code } = req.body;
  const list = deviceLinkRequests.get(req.params.ownerFipId) || [];
  const idx = list.findIndex(r => r.requesterFipId === requesterFipId);
  if (idx === -1) return res.status(404).json({ error: 'not-found' });
  list[idx].attempts = (list[idx].attempts || 0) + 1;
  const attempts = list[idx].attempts; // capture before possible splice
  const ok = list[idx].code === code;
  if (ok) {
    deviceLinkStatus.set(requesterFipId, { status: 'linked' });
    // Track deviceId -> requesterFipId so kick can target the right entry.
    const linkedDeviceId = req.body.deviceId || `${req.params.ownerFipId}_${requesterFipId}`;
    deviceIdToRequester.set(linkedDeviceId, requesterFipId);
    list.splice(idx, 1); // clean up pending
  } else if (attempts >= 3) {
    deviceLinkStatus.set(requesterFipId, { status: 'fake' });
    // Auto-ban after 3 failures
    if (!deviceBans.has(req.params.ownerFipId)) deviceBans.set(req.params.ownerFipId, new Set());
    deviceBans.get(req.params.ownerFipId).add(requesterFipId);
    list.splice(idx, 1);
  } else {
    deviceLinkStatus.set(requesterFipId, { status: 'retry', attempt: attempts });
  }
  deviceLinkRequests.set(req.params.ownerFipId, list);
  res.json({ ok, attempts });
});
app.delete('/device-link/:ownerFipId/:deviceId', (req, res) => {
  // Kick a linked device (removes activity log + revokes link status; ban prevents re-link)
  deviceActivities.delete(`${req.params.ownerFipId}_${req.params.deviceId}`);
  const requesterFipId = deviceIdToRequester.get(req.params.deviceId);
  if (requesterFipId) {
    deviceLinkStatus.set(requesterFipId, { status: 'kicked' });
    deviceIdToRequester.delete(req.params.deviceId);
  }
  res.sendStatus(200);
});

app.post('/device-activity/:ownerFipId', (req, res) => {
  const key = `${req.params.ownerFipId}_${req.body.deviceId}`;
  const list = deviceActivities.get(key) || [];
  list.push(req.body);
  if (list.length > 500) list.splice(0, list.length - 500);
  deviceActivities.set(key, list);
  res.sendStatus(200);
});
app.get('/device-activity/:ownerFipId/:deviceId', (req, res) => {
  const key = `${req.params.ownerFipId}_${req.params.deviceId}`;
  res.json(deviceActivities.get(key) || []);
});

app.post('/device-ban/:ownerFipId', (req, res) => {
  if (!deviceBans.has(req.params.ownerFipId)) deviceBans.set(req.params.ownerFipId, new Set());
  deviceBans.get(req.params.ownerFipId).add(req.body.bannedFipId);
  res.sendStatus(200);
});
app.get('/device-ban/:ownerFipId', (req, res) => {
  res.json([...(deviceBans.get(req.params.ownerFipId) || new Set())]);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Photon Chat server running on port ${PORT}`));
