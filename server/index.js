const express = require('express');
const app = express();
app.use(express.json());

// --- In-memory store ---
const users = new Map();       // fipId -> { code, name, ts }
const requests = new Map();    // toFipId -> [{ fromFipId, fromCode, fromName, fromServerUrl, ts }]
const accepted = new Map();    // myFipId -> Set<otherFipId>
const chats = new Map();       // chatKey -> [{ from, text, ts }]
const groups = new Map();      // groupId -> { groupId, groupCode, name, ownerFipId, ownerServerUrl, members: [], joinRequests: [], messages: [] }

function rand(n) {
  return Math.floor(Math.random() * Math.pow(10, n)).toString().padStart(n, '0');
}

// --- Presence ---
app.post('/presence', (req, res) => {
  const { fipId, code, name } = req.body;
  if (!fipId) return res.sendStatus(400);
  users.set(fipId, { code, name, ts: Date.now() });
  res.sendStatus(200);
});

app.get('/lookup/:code', (req, res) => {
  for (const [fipId, u] of users) {
    if (u.code === req.params.code) return res.json({ fipId, ...u });
  }
  res.sendStatus(404);
});

// --- Friend requests ---
app.post('/requests/:toFipId', (req, res) => {
  const { toFipId } = req.params;
  const { fromFipId, fromCode, fromName, fromServerUrl } = req.body;
  if (!requests.has(toFipId)) requests.set(toFipId, []);
  const list = requests.get(toFipId);
  if (!list.find(r => r.fromFipId === fromFipId)) {
    list.push({ fromFipId, fromCode, fromName, fromServerUrl, ts: Date.now() });
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
  // Remove from pending
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

app.post('/chat/:chatKey', (req, res) => {
  const key = req.params.chatKey;
  if (!chats.has(key)) chats.set(key, []);
  const msgs = chats.get(key);
  msgs.push(req.body);
  if (msgs.length > 200) msgs.splice(0, msgs.length - 200);
  res.sendStatus(200);
});

app.delete('/chat/:chatKey', (req, res) => {
  chats.delete(req.params.chatKey);
  res.sendStatus(200);
});

// --- Deactivate ---
app.post('/deactivate', (req, res) => {
  const { fipId } = req.body;
  users.delete(fipId);
  requests.delete(fipId);
  accepted.delete(fipId);
  for (const [key] of chats) {
    if (key.includes(fipId)) chats.delete(key);
  }
  for (const [, g] of groups) {
    g.members = g.members.filter(m => m.fipId !== fipId);
    g.joinRequests = g.joinRequests.filter(r => r.fromFipId !== fipId);
  }
  res.sendStatus(200);
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
    joinRequests: [],
    messages: [],
  });
  res.json({ groupId, groupCode, name, ownerFipId, ownerServerUrl });
});

app.get('/groups/by-code/:code', (req, res) => {
  for (const [, g] of groups) {
    if (g.groupCode === req.params.code) {
      return res.json({ groupId: g.groupId, groupCode: g.groupCode, name: g.name, ownerFipId: g.ownerFipId, ownerServerUrl: g.ownerServerUrl });
    }
  }
  res.sendStatus(404);
});

app.post('/groups/:groupId/join-requests', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  const { fromFipId, fromName, fromServerUrl } = req.body;
  if (!g.joinRequests.find(r => r.fromFipId === fromFipId)) {
    g.joinRequests.push({ fromFipId, fromName, fromServerUrl, ts: Date.now() });
  }
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
  if (!g.members.find(m => m.fipId === fipId)) {
    g.members.push({ fipId, name, serverUrl });
  }
  g.joinRequests = g.joinRequests.filter(r => r.fromFipId !== fipId);
  res.sendStatus(200);
});

app.delete('/groups/:groupId/members/:fipId', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  g.members = g.members.filter(m => m.fipId !== req.params.fipId);
  res.sendStatus(200);
});

// Group messages — 10-sender-per-server limit
app.post('/groups/:groupId/messages', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  const { from, fromName, text, ts } = req.body;
  const uniqueSenders = [...new Set(g.messages.map(m => m.from))];
  if (!uniqueSenders.includes(from) && uniqueSenders.length >= 10) {
    return res.status(429).json({ error: 'Slot limit reached (10 senders max)' });
  }
  g.messages.push({ from, fromName, text, ts: ts || Date.now() });
  if (g.messages.length > 500) g.messages.splice(0, g.messages.length - 500);
  res.sendStatus(200);
});

app.get('/groups/:groupId/messages', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  res.json(g.messages);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Photon Chat server running on port ${PORT}`));
