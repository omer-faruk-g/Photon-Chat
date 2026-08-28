#!/usr/bin/env node
// Boots server/index.js on a scratch port and exercises it over real HTTP.
// Covers the happy path a client actually walks, plus the auth negatives that
// silently regressed before (an endpoint answering 403 to its own legitimate
// caller looks identical to "network is down" in the app).
//
// Usage: node tool/server_test.js

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const PORT = 3987;
const BASE = `http://127.0.0.1:${PORT}`;
const SNAPSHOT = path.join(os.tmpdir(), `photon-test-snapshot-${process.pid}.json`);

// Real identity shape: FipBlock._deriveFipId returns 'fip_<16 hex>'. The
// underscore matters — chat keys are built from these.
const A = { fipId: 'fip_aaaaaaaaaaaaaaa1', code: '11111', name: 'Ayse', url: BASE };
const B = { fipId: 'fip_bbbbbbbbbbbbbbb2', code: '22222', name: 'Burak', url: BASE };
const EVE = { fipId: 'fip_eeeeeeeeeeeeeee3', code: '33333', name: 'Eve', url: BASE };

// Mirrors chatKeyFor() in lib/fip.dart — note the DOUBLE underscore.
const chatKeyFor = (a, b) => [a, b].sort().join('__');

let pass = 0;
const failures = [];
function check(name, ok, detail) {
  if (ok) { pass++; return; }
  failures.push(`${name}${detail ? ` — ${detail}` : ''}`);
}

async function req(method, p, body) {
  const res = await fetch(BASE + p, {
    method,
    headers: body === undefined ? {} : { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let data = null;
  const text = await res.text();
  if (text) { try { data = JSON.parse(text); } catch { data = text; } }
  return { status: res.status, data };
}
const GET = (p) => req('GET', p);
const POST = (p, b) => req('POST', p, b);
const PUT = (p, b) => req('PUT', p, b);
const DEL = (p, b) => req('DELETE', p, b);

async function waitForServer(proc) {
  for (let i = 0; i < 60; i++) {
    if (proc.exitCode !== null) throw new Error(`server exited early (code ${proc.exitCode})`);
    try {
      const r = await fetch(`${BASE}/lookup/00000`);
      if (r.status === 404 || r.status === 200) return;
    } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error('server did not come up within 12s');
}

async function run() {
  // ---- presence / lookup ----------------------------------------------------
  for (const u of [A, B, EVE]) {
    const r = await POST('/presence', {
      fipId: u.fipId, code: u.code, name: u.name, serverUrl: u.url, publicKey: 'pk-' + u.code,
    });
    check(`presence ${u.name}`, r.status === 200, `status ${r.status}`);
  }
  const look = await GET(`/lookup/${B.code}`);
  check('lookup by code', look.status === 200 && look.data.fipId === B.fipId, JSON.stringify(look.data));

  const prof = await GET(`/profile/${A.fipId}`);
  check('profile fetch', prof.status === 200 && prof.data.name === 'Ayse', `status ${prof.status}`);

  const act = await POST('/active', { fipIds: [A.fipId, B.fipId, 'fip_nope'] });
  check('active filter', act.status === 200 && act.data.length === 2, JSON.stringify(act.data));

  // ---- friend request / accept ---------------------------------------------
  let r = await POST(`/requests/${B.fipId}`, {
    fromFipId: A.fipId, fromCode: A.code, fromName: A.name, fromServerUrl: A.url,
  });
  check('send friend request', r.status === 200, `status ${r.status}`);

  r = await GET(`/requests/${B.fipId}`);
  check('list friend requests', r.status === 200 && r.data.length === 1, JSON.stringify(r.data));

  r = await POST('/accept', { myFipId: B.fipId, otherFipId: A.fipId, actor: B.fipId });
  check('accept request', r.status === 200, `status ${r.status}`);

  r = await POST('/accept', { myFipId: B.fipId, otherFipId: EVE.fipId, actor: EVE.fipId });
  check('AUTH accept as someone else rejected', r.status === 403, `status ${r.status}`);

  r = await GET(`/accepted/${B.fipId}`);
  check('accepted list', r.status === 200 && r.data.includes(A.fipId), JSON.stringify(r.data));

  // The link must exist on BOTH sides from that single accept. This used to be
  // papered over here by accepting again as A, which hid the fact that the
  // inviter never learned they had been accepted and sat on "waiting for
  // approval" forever.
  r = await GET(`/accepted/${A.fipId}`);
  check('accept is mutual (inviter sees it too)',
    r.status === 200 && r.data.includes(B.fipId), JSON.stringify(r.data));

  // ---- direct messages ------------------------------------------------------
  // The client posts `from`, not `fromFipId`; the server must accept both.
  const ck = chatKeyFor(A.fipId, B.fipId);
  r = await POST(`/chat/${ck}`, {
    from: A.fipId, toFipId: B.fipId, fromName: A.name, text: 'merhaba', ts: Date.now(),
  });
  check('send DM (client sends `from`)', r.status === 200 && r.data && r.data.msgId, `status ${r.status} ${JSON.stringify(r.data)}`);
  const msgId = r.data && r.data.msgId;

  r = await GET(`/chat/${ck}`);
  check('read DM back', r.status === 200 && r.data.length === 1 && r.data[0].text === 'merhaba', JSON.stringify(r.data));
  check('DM carries a `from` field the client can read', r.status === 200 && r.data[0] && r.data[0].from === A.fipId, JSON.stringify(r.data[0]));

  // image / file payloads must survive the whitelist
  r = await POST(`/chat/${ck}`, {
    from: A.fipId, toFipId: B.fipId, fromName: A.name, text: '[foto]', ts: Date.now(),
    type: 'image', imageData: 'BASE64DATA', nsfw: true,
  });
  check('send image DM', r.status === 200, `status ${r.status}`);
  r = await GET(`/chat/${ck}`);
  const img = r.data.find((m) => m.type === 'image');
  check('image payload preserved', !!img && img.imageData === 'BASE64DATA' && img.nsfw === true, JSON.stringify(img));

  r = await POST(`/chat/${ck}`, {
    from: A.fipId, toFipId: B.fipId, fromName: A.name, text: '[Dosya: x.pdf]', ts: Date.now(),
    type: 'file', fileName: 'x.pdf', fileData: 'FILEB64', fileSize: 42,
  });
  check('send file DM', r.status === 200, `status ${r.status}`);
  r = await GET(`/chat/${ck}`);
  const file = r.data.find((m) => m.type === 'file');
  check('file payload preserved', !!file && file.fileData === 'FILEB64' && file.fileSize === 42, JSON.stringify(file));

  r = await POST(`/chat/${ck}`, { from: EVE.fipId, text: 'sizi dinliyorum', ts: Date.now() });
  check('AUTH outsider cannot post into a chat', r.status === 403, `status ${r.status}`);

  r = await PUT(`/chat/${ck}/msg/${msgId}`, { text: 'duzeltildi', actor: A.fipId });
  check('edit own message', r.status === 200, `status ${r.status}`);
  r = await PUT(`/chat/${ck}/msg/${msgId}`, { text: 'hack', actor: EVE.fipId });
  check('AUTH cannot edit someone else message', r.status === 403, `status ${r.status}`);

  r = await POST(`/chat/${ck}/msg/${msgId}/react`, { fipId: B.fipId, emoji: '👍', actor: B.fipId });
  check('react to message', r.status === 200, `status ${r.status}`);
  r = await GET(`/chat/${ck}/reactions`);
  check('read reactions', r.status === 200 && r.data[msgId] && r.data[msgId]['👍'].includes(B.fipId), JSON.stringify(r.data));
  r = await POST(`/chat/${ck}/msg/${msgId}/react`, { fipId: EVE.fipId, emoji: '👎', actor: EVE.fipId });
  check('AUTH outsider cannot react', r.status === 403, `status ${r.status}`);

  r = await POST(`/chat/${ck}/read`, { fipId: B.fipId, actor: B.fipId });
  check('mark read', r.status === 200, `status ${r.status}`);
  r = await GET(`/chat/${ck}/read`);
  check('read receipts', r.status === 200 && r.data[B.fipId], JSON.stringify(r.data));

  r = await POST(`/typing/${ck}`, { fipId: A.fipId, actor: A.fipId, ts: Date.now() });
  check('typing ping', r.status === 200, `status ${r.status}`);
  r = await GET(`/typing/${ck}`);
  check('typing list', r.status === 200 && r.data.length === 1, JSON.stringify(r.data));

  r = await DEL(`/chat/${ck}/msg/${msgId}`, { actor: EVE.fipId });
  check('AUTH cannot delete someone else message', r.status === 403, `status ${r.status}`);
  r = await DEL(`/chat/${ck}/msg/${msgId}`, { actor: A.fipId });
  check('delete own message', r.status === 200, `status ${r.status}`);

  // ---- notifications --------------------------------------------------------
  r = await POST(`/notifs/${B.fipId}`, { title: 'selam', body: 'gövde', actor: A.fipId });
  check('notif from accepted contact', r.status === 200, `status ${r.status}`);
  r = await POST(`/notifs/${B.fipId}`, { title: 'spam', body: 'spam', actor: EVE.fipId });
  check('AUTH notif from stranger rejected', r.status === 403, `status ${r.status}`);
  r = await POST(`/notifs/${B.fipId}`, { title: 'spam', body: 'spam' });
  check('AUTH anonymous notif rejected', r.status === 403, `status ${r.status}`);
  r = await GET(`/notifs/${B.fipId}`);
  // Two entries expected: the auto-notify raised by the earlier DM, plus the
  // explicit one above. The stranger/anonymous attempts must not appear.
  check('notif list holds only authorised entries', r.status === 200 && r.data.length === 2, JSON.stringify(r.data));
  const auto = r.data.find((n) => n.title === '__NEW_MESSAGE__');
  check('auto-notify uses locale-neutral tags', !!auto && auto.body === '__NEW_MESSAGE_FROM__' && auto.bodyName === A.name, JSON.stringify(auto));
  check('no spam reached the tray', !r.data.some((n) => n.title === 'spam'), JSON.stringify(r.data));

  // ---- paid tiers -----------------------------------------------------------
  r = await GET(`/tier/${A.fipId}`);
  check('tier defaults to none', r.status === 200 && r.data.tier === 'none', JSON.stringify(r.data));

  r = await POST('/tier/grant', { fipId: A.fipId, tier: 'bogusTier', months: 1 });
  check('unknown tier rejected', r.status === 400, `status ${r.status}`);

  r = await POST('/tier/grant', { fipId: A.fipId, tier: 'vip', months: 1 });
  check('grant vip', r.status === 200 && r.data.tier === 'vip', JSON.stringify(r.data));
  check('grant sets a future expiry', r.data && r.data.expiresAt > Date.now(), JSON.stringify(r.data));

  r = await POST(`/tier/${A.fipId}/prefs`, { color: 123456, actor: EVE.fipId });
  check('AUTH cannot set another user tier prefs', r.status === 403, `status ${r.status}`);

  r = await POST(`/tier/${A.fipId}/prefs`, { color: 123456, actor: A.fipId });
  check('owner sets colour', r.status === 200 && r.data.color === 123456, JSON.stringify(r.data));

  // Alias is a photonPulseVip perk. A vip subscriber setting one must not have
  // it reported to peers, or the top tier is free.
  r = await POST(`/tier/${A.fipId}/prefs`, { fakeName: 'Gizli', fakeActive: true, actor: A.fipId });
  check('fake name accepted but not honoured below top tier',
    r.status === 200 && r.data.fakeActive === false && r.data.fakeName === '', JSON.stringify(r.data));

  r = await POST('/tier/grant', { fipId: A.fipId, tier: 'photonPulseVip', months: 1 });
  check('upgrade to photonPulseVip', r.status === 200 && r.data.tier === 'photonPulseVip', JSON.stringify(r.data));
  r = await GET(`/tier/${A.fipId}`);
  check('alias honoured at top tier', r.data.fakeActive === true && r.data.fakeName === 'Gizli', JSON.stringify(r.data));

  r = await POST(`/tier/${A.fipId}/prefs`, { fakeName: '   ', actor: A.fipId });
  check('blank alias does not activate', r.status === 200 && r.data.fakeActive === false, JSON.stringify(r.data));
  await POST(`/tier/${A.fipId}/prefs`, { fakeName: 'Gizli', actor: A.fipId });

  r = await POST(`/tier/${B.fipId}/prefs`, { color: 1, actor: B.fipId });
  check('prefs rejected without a subscription', r.status === 403, `status ${r.status}`);

  r = await POST('/tiers/batch', { fipIds: [A.fipId, B.fipId, 'fip_nobody'] });
  check('batch returns one entry per id',
    r.status === 200 && r.data[A.fipId].tier === 'photonPulseVip' && r.data[B.fipId].tier === 'none',
    JSON.stringify(r.data));

  // ---- bridge registry ------------------------------------------------------
  r = await POST('/registry/register', { code: A.code, serverUrl: A.url, actor: A.fipId });
  check('registry claim', r.status === 200, `status ${r.status}`);
  r = await GET(`/registry/lookup/${A.code}`);
  check('registry lookup', r.status === 200 && r.data.serverUrl === A.url, JSON.stringify(r.data));
  r = await POST('/registry/register', { code: A.code, serverUrl: 'http://evil.example', actor: EVE.fipId });
  check('AUTH registry hijack rejected', r.status === 403, `status ${r.status}`);
  r = await GET(`/registry/lookup/${A.code}`);
  check('registry unchanged after hijack attempt', r.data.serverUrl === A.url, JSON.stringify(r.data));
  r = await POST('/registry/register', { code: A.code, serverUrl: 'http://new.example', actor: A.fipId });
  check('owner may repoint own code', r.status === 200, `status ${r.status}`);

  // ---- groups ---------------------------------------------------------------
  r = await POST('/groups', {
    ownerFipId: A.fipId, ownerName: A.name, name: 'Takim',
    ownerServerUrl: A.url, description: 'Proje ekibi', actor: A.fipId,
  });
  check('create group', r.status === 200 && r.data.groupId, JSON.stringify(r.data));
  const gid = r.data && r.data.groupId;
  const gcode = r.data && r.data.groupCode;

  r = await POST('/groups', { ownerFipId: A.fipId, ownerName: A.name, name: 'Sahte', ownerServerUrl: A.url, actor: EVE.fipId });
  check('AUTH cannot create group as someone else', r.status === 403, `status ${r.status}`);

  r = await GET(`/groups/by-code/${gcode}`);
  check('group by code', r.status === 200 && r.data.groupId === gid, JSON.stringify(r.data));
  // The joiner reads description off this response; it used to always be empty.
  check('group description reaches joiners', r.data && r.data.description === 'Proje ekibi', JSON.stringify(r.data));

  r = await POST(`/groups/${gid}/join-requests`, { fromFipId: B.fipId, fromName: B.name, fromServerUrl: B.url, actor: B.fipId });
  check('join request', r.status === 200, `status ${r.status}`);
  r = await GET(`/groups/${gid}/join-requests`);
  check('join request listed', r.status === 200 && r.data.length === 1, JSON.stringify(r.data));

  r = await POST(`/groups/${gid}/members`, { fipId: B.fipId, name: B.name, serverUrl: B.url, actor: A.fipId });
  check('owner adds member', r.status === 200, `status ${r.status}`);
  r = await GET(`/groups/${gid}/members`);
  check('member list', r.status === 200 && r.data.members.length === 2, JSON.stringify(r.data));

  r = await POST(`/groups/${gid}/members`, { fipId: EVE.fipId, name: EVE.name, serverUrl: EVE.url, actor: EVE.fipId });
  check('AUTH self-add without approval rejected', r.status === 403, `status ${r.status}`);

  r = await POST(`/groups/${gid}/messages`, { from: B.fipId, fromName: B.name, text: 'selam takim', ts: Date.now(), actor: B.fipId });
  check('member posts group message', r.status === 200, `status ${r.status}`);
  r = await POST(`/groups/${gid}/messages`, { from: EVE.fipId, fromName: EVE.name, text: 'sizi buldum', ts: Date.now(), actor: EVE.fipId });
  check('AUTH non-member cannot post to group', r.status === 403, `status ${r.status}`);

  // poll
  r = await POST(`/groups/${gid}/messages`, {
    from: A.fipId, fromName: A.name, type: 'poll', question: 'Nerede?',
    options: ['Ev', 'Ofis'], votes: { [EVE.fipId]: 1 }, ts: Date.now(), actor: A.fipId,
  });
  check('create poll', r.status === 200, `status ${r.status}`);
  const pollId = r.data && r.data.msgId;
  r = await GET(`/groups/${gid}/messages`);
  const poll = r.data.find((m) => m.msgId === pollId);
  check('poll stored with question and options', !!poll && poll.question === 'Nerede?' && poll.options.length === 2, JSON.stringify(poll));
  check('client-supplied votes ignored on create', !!poll && Object.keys(poll.votes || {}).length === 0, JSON.stringify(poll && poll.votes));

  r = await POST(`/groups/${gid}/messages/${pollId}/vote`, { fipId: B.fipId, optionIndex: 1, actor: B.fipId });
  check('member votes', r.status === 200, `status ${r.status}`);
  r = await POST(`/groups/${gid}/messages/${pollId}/vote`, { fipId: EVE.fipId, optionIndex: 0, actor: EVE.fipId });
  check('AUTH non-member cannot vote', r.status === 403, `status ${r.status}`);
  r = await GET(`/groups/${gid}/messages`);
  const poll2 = r.data.find((m) => m.msgId === pollId);
  check('vote recorded', poll2 && poll2.votes[B.fipId] === 1, JSON.stringify(poll2 && poll2.votes));

  // announcements
  r = await POST(`/groups/${gid}/announce`, { from: A.fipId, fromName: A.name, text: 'duyuru', actor: A.fipId });
  check('owner announces', r.status === 200, `status ${r.status}`);
  r = await POST(`/groups/${gid}/announce`, { from: B.fipId, fromName: B.name, text: 'ben de', actor: B.fipId });
  check('AUTH non-owner cannot announce', r.status === 403, `status ${r.status}`);
  r = await GET(`/groups/${gid}/announcements`);
  check('announcement listed', r.status === 200 && r.data.length === 1, JSON.stringify(r.data));

  // mute
  r = await POST(`/groups/${gid}/muted`, { fipId: B.fipId, actor: A.fipId });
  check('owner mutes member', r.status === 200, `status ${r.status}`);
  r = await POST(`/groups/${gid}/messages`, { from: B.fipId, fromName: B.name, text: 'susturuldum mu', ts: Date.now(), actor: B.fipId });
  check('muted member cannot post', r.status === 403, `status ${r.status}`);
  r = await DEL(`/groups/${gid}/muted/${B.fipId}`, { actor: EVE.fipId });
  check('AUTH non-owner cannot unmute', r.status === 403, `status ${r.status}`);
  r = await DEL(`/groups/${gid}/muted/${B.fipId}`, { actor: A.fipId });
  check('owner unmutes', r.status === 200, `status ${r.status}`);

  // group key
  r = await POST(`/groups/${gid}/key/${B.fipId}`, { encryptedKey: 'WRAPPEDKEY', actor: A.fipId });
  check('owner publishes group key', r.status === 200, `status ${r.status}`);
  r = await POST(`/groups/${gid}/key/${B.fipId}`, { encryptedKey: 'EVIL', actor: EVE.fipId });
  check('AUTH non-owner cannot publish group key', r.status === 403, `status ${r.status}`);
  r = await GET(`/groups/${gid}/key/${B.fipId}`);
  check('member reads group key', r.status === 200 && r.data.encryptedKey === 'WRAPPEDKEY', JSON.stringify(r.data));

  r = await DEL(`/groups/${gid}/members/${B.fipId}`, { actor: EVE.fipId });
  check('AUTH outsider cannot kick', r.status === 403, `status ${r.status}`);
  r = await DEL(`/groups/${gid}/members/${B.fipId}`, { actor: A.fipId });
  check('owner kicks member', r.status === 200, `status ${r.status}`);

  // ---- stories --------------------------------------------------------------
  // Client posts StoryItem.toJson(): id/authorFipId/authorName/type/content/ts/expiresAt
  const story = {
    id: `${A.fipId}_1`, authorFipId: A.fipId, authorName: A.name,
    type: 'text', content: 'ilk hikayem', ts: Date.now(),
    expiresAt: Date.now() + 86400000, actor: A.fipId,
  };
  r = await POST(`/stories/${A.fipId}`, story);
  check('post story', r.status === 200, `status ${r.status}`);
  r = await GET(`/stories/${A.fipId}`);
  const s0 = r.data && r.data[0];
  check('story type/content survive', !!s0 && s0.type === 'text' && s0.content === 'ilk hikayem', JSON.stringify(s0));
  check('story author survives', !!s0 && s0.authorFipId === A.fipId && s0.authorName === A.name, JSON.stringify(s0));
  r = await POST(`/stories/${A.fipId}`, { ...story, id: 'x2', actor: EVE.fipId });
  check('AUTH cannot post story as someone else', r.status === 403, `status ${r.status}`);
  r = await DEL(`/stories/${A.fipId}/${story.id}`, { actor: EVE.fipId });
  check('AUTH cannot delete someone else story', r.status === 403, `status ${r.status}`);
  r = await DEL(`/stories/${A.fipId}/${story.id}`, { actor: A.fipId });
  check('delete own story', r.status === 200, `status ${r.status}`);

  // ---- device link ----------------------------------------------------------
  r = await POST(`/device-link/${A.fipId}`, { requesterFipId: B.fipId, requesterName: B.name, requesterServerUrl: B.url });
  check('device link request', r.status === 200, `status ${r.status}`);
  r = await GET(`/device-link/${A.fipId}`);
  check('device link listed', r.status === 200 && r.data.length === 1, JSON.stringify(r.data));
  r = await POST(`/device-link/${A.fipId}/respond`, { requesterFipId: B.fipId, status: 'approved', code: '9999', actor: EVE.fipId });
  check('AUTH cannot respond to someone else device link', r.status === 403, `status ${r.status}`);
  r = await POST(`/device-link/${A.fipId}/respond`, { requesterFipId: B.fipId, status: 'approved', code: 'x'.repeat(500), actor: A.fipId });
  check('oversized device-link code rejected', r.status === 400, `status ${r.status}`);
  r = await POST(`/device-link/${A.fipId}/respond`, { requesterFipId: B.fipId, status: 'approved', code: '9999', actor: A.fipId });
  check('owner responds to device link', r.status === 200, `status ${r.status}`);
  r = await GET(`/device-link-status/${B.fipId}`);
  check('device link status', r.status === 200 && r.data.status === 'approved', JSON.stringify(r.data));
  r = await POST(`/device-link/${A.fipId}/verify`, { requesterFipId: B.fipId, code: '9999', actor: B.fipId, deviceId: 'dev1' });
  check('device link verify ok', r.status === 200 && r.data.ok === true, JSON.stringify(r.data));

  r = await POST(`/device-activity/${A.fipId}`, { deviceId: 'dev1', action: 'login', detail: '', actor: A.fipId });
  check('device activity log', r.status === 200, `status ${r.status}`);
  r = await POST(`/device-activity/${A.fipId}`, { deviceId: 'dev1', action: 'login', detail: '', actor: EVE.fipId });
  check('AUTH stranger cannot log device activity', r.status === 403, `status ${r.status}`);
  r = await GET(`/device-activity/${A.fipId}/dev1`);
  check('device activity listed', r.status === 200 && r.data.length === 1, JSON.stringify(r.data));

  r = await POST(`/device-ban/${A.fipId}`, { bannedFipId: EVE.fipId, actor: EVE.fipId });
  check('AUTH cannot ban on someone else account', r.status === 403, `status ${r.status}`);
  r = await POST(`/device-ban/${A.fipId}`, { bannedFipId: EVE.fipId, actor: A.fipId });
  check('owner bans device', r.status === 200, `status ${r.status}`);
  r = await GET(`/device-ban/${A.fipId}`);
  check('ban listed', r.status === 200 && r.data.includes(EVE.fipId), JSON.stringify(r.data));

  r = await DEL(`/device-link/${A.fipId}/dev1`, { actor: EVE.fipId });
  check('AUTH stranger cannot kick device', r.status === 403, `status ${r.status}`);
  r = await DEL(`/device-link/${A.fipId}/dev1`, { actor: A.fipId });
  check('owner kicks device', r.status === 200, `status ${r.status}`);

  // ---- chat deletion --------------------------------------------------------
  r = await DEL(`/chat/${ck}`, { actor: EVE.fipId });
  check('AUTH outsider cannot delete chat', r.status === 403, `status ${r.status}`);
  r = await DEL(`/chat/${ck}`, { actor: A.fipId });
  check('participant deletes chat', r.status === 200, `status ${r.status}`);
  r = await GET(`/chat/${ck}`);
  check('chat is empty after delete', r.status === 200 && r.data.length === 0, JSON.stringify(r.data));

  // ---- deactivate -----------------------------------------------------------
  r = await POST('/deactivate', { fipId: EVE.fipId, actor: A.fipId });
  check('AUTH cannot deactivate someone else', r.status === 403, `status ${r.status}`);
  r = await POST('/deactivate', { fipId: EVE.fipId, actor: EVE.fipId });
  check('deactivate self', r.status === 200, `status ${r.status}`);
  r = await GET(`/profile/${EVE.fipId}`);
  check('deactivated profile gone', r.status === 404, `status ${r.status}`);
}

function boot(snapshotFile) {
  const proc = spawn(process.execPath, [path.join(__dirname, '..', 'server', 'index.js')], {
    env: { ...process.env, PORT: String(PORT), SNAPSHOT_FILE: snapshotFile },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  proc.stdout.on('data', (d) => { proc._log = (proc._log || '') + d; });
  proc.stderr.on('data', (d) => { proc._log = (proc._log || '') + d; });
  return proc;
}

// Reactions and chats must survive a restart. The index that powers
// GET /chat/:chatKey/reactions used to be rebuilt by string-splitting a
// composite key, which corrupted it on every reload.
async function restartRun() {
  const ck = chatKeyFor(A.fipId, B.fipId);
  const mid = '1699999999_ab3de'; // real shape: `${ts}_${rand}`
  fs.writeFileSync(SNAPSHOT, JSON.stringify({
    users: { [A.fipId]: { code: A.code, name: A.name, serverUrl: A.url, lastSeen: Date.now() } },
    chats: { [ck]: [{ from: A.fipId, fromFipId: A.fipId, text: 'kalici', ts: Date.now(), msgId: mid }] },
    chatReactions: { [`${ck}_${mid}`]: { '👍': [B.fipId] } },
    reactionsByChat: { [ck]: [mid] },
    tiers: {
      [A.fipId]: { tier: 'photonPulseVip', expiresAt: Date.now() - 1000, fakeName: 'Gizli', fakeActive: true },
      [B.fipId]: { tier: 'pvip', expiresAt: Date.now() + 60_000 },
    },
  }));

  const proc = boot(SNAPSHOT);
  try {
    await waitForServer(proc);
    let r = await GET(`/chat/${ck}`);
    check('restart: chat history restored', r.status === 200 && r.data.length === 1 && r.data[0].text === 'kalici', JSON.stringify(r.data));
    r = await GET(`/chat/${ck}/reactions`);
    check('restart: reactions still reachable', r.status === 200 && r.data[mid] && r.data[mid]['👍'].includes(B.fipId), JSON.stringify(r.data));
    r = await GET(`/lookup/${A.code}`);
    check('restart: code index rebuilt', r.status === 200 && r.data.fipId === A.fipId, JSON.stringify(r.data));
    r = await GET(`/tier/${A.fipId}`);
    check('restart: lapsed subscription reads as none', r.data.tier === 'none' && r.data.fakeActive === false, JSON.stringify(r.data));
    r = await GET(`/tier/${B.fipId}`);
    check('restart: live subscription survives', r.data.tier === 'pvip', JSON.stringify(r.data));
  } catch (e) {
    failures.push(`restart harness error: ${e.message}`);
  } finally {
    proc.kill('SIGKILL');
  }
}

(async () => {
  try { fs.unlinkSync(SNAPSHOT); } catch { /* fine */ }
  const proc = boot(SNAPSHOT);
  let serverLog = '';

  let exitCode = 0;
  try {
    await waitForServer(proc);
    await run();
  } catch (e) {
    failures.push(`harness error: ${e.message}`);
  } finally {
    serverLog = proc._log || '';
    proc.kill('SIGKILL');
    await new Promise((r) => setTimeout(r, 300));
  }

  await restartRun();
  try { fs.unlinkSync(SNAPSHOT); } catch { /* fine */ }

  console.log(`\npassed: ${pass}   failed: ${failures.length}`);
  if (failures.length) {
    console.error('\nFAILURES:');
    for (const f of failures) console.error('  ✗ ' + f);
    if (serverLog.trim()) console.error('\n--- server output ---\n' + serverLog.trim());
    exitCode = 1;
  } else {
    console.log('all server checks passed.');
  }
  process.exit(exitCode);
})();
