const express = require('express');
const app = express();
app.use(express.json());

// --- In-memory store ---
const users = new Map();
const requests = new Map();
const accepted = new Map();
const chats = new Map();
const groups = new Map();
const typingMap = new Map(); // chatKey -> [{fipId, ts}]

function rand(n) {
  return Math.floor(Math.random() * Math.pow(10, n)).toString().padStart(n, '0');
}

// --- Presence ---
app.post('/presence', (req, res) => {
  const { fipId, code, name, publicKey } = req.body;
  if (!fipId) return res.sendStatus(400);
  users.set(fipId, { code, name, publicKey, ts: Date.now() });
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
  const { fromFipId, fromCode, fromName, fromServerUrl, fromPublicKey } = req.body;
  if (!requests.has(toFipId)) requests.set(toFipId, []);
  const list = requests.get(toFipId);
  if (!list.find(r => r.fromFipId === fromFipId)) {
    list.push({ fromFipId, fromCode, fromName, fromServerUrl, fromPublicKey, ts: Date.now() });
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
  users.delete(fipId);
  requests.delete(fipId);
  accepted.delete(fipId);
  for (const [key] of chats) {
    if (key.includes(fipId)) chats.delete(key);
  }
  for (const [key] of typingMap) {
    if (key.includes(fipId)) typingMap.delete(key);
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
    joinRequests: [], messages: [],
    muted: [],       // susturulan üyeler [fipId, ...]
    groupKeys: {},   // { memberFipId: encryptedKey }
  });
  res.json({ groupId, groupCode, name, ownerFipId, ownerServerUrl });
});

app.get('/groups/by-code/:code', (req, res) => {
  for (const [, g] of groups) {
    if (g.groupCode === req.params.code)
      return res.json({ groupId: g.groupId, groupCode: g.groupCode, name: g.name, ownerFipId: g.ownerFipId, ownerServerUrl: g.ownerServerUrl });
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

app.delete('/groups/:groupId/members/:fipId', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  g.members = g.members.filter(m => m.fipId !== req.params.fipId);
  // Susturma listesinden de çıkar
  g.muted = (g.muted || []).filter(id => id !== req.params.fipId);
  res.sendStatus(200);
});

// --- Group mute ---
app.post('/groups/:groupId/muted', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  const { fipId } = req.body;
  if (!fipId) return res.sendStatus(400);
  if (!g.muted) g.muted = [];
  if (!g.muted.includes(fipId)) g.muted.push(fipId);
  res.sendStatus(200);
});

app.delete('/groups/:groupId/muted/:fipId', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  if (!g.muted) g.muted = [];
  g.muted = g.muted.filter(id => id !== req.params.fipId);
  res.sendStatus(200);
});

app.get('/groups/:groupId/muted', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  res.json(g.muted || []);
});

// --- Group messages (muted kontrolü) ---
app.post('/groups/:groupId/messages', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  const { from, fromName, text, ts } = req.body;
  // Susturulan kullanıcı mesaj gönderemez
  if ((g.muted || []).includes(from)) {
    return res.status(403).json({ error: 'Susturuldunuz.' });
  }
  const uniqueSenders = [...new Set(g.messages.map(m => m.from))];
  if (!uniqueSenders.includes(from) && uniqueSenders.length >= 10)
    return res.status(429).json({ error: 'Slot limit reached (10 senders max)' });
  g.messages.push({ from, fromName, text, ts: ts || Date.now() });
  if (g.messages.length > 500) g.messages.splice(0, g.messages.length - 500);
  res.sendStatus(200);
});

app.get('/groups/:groupId/messages', (req, res) => {
  const g = groups.get(req.params.groupId);
  if (!g) return res.sendStatus(404);
  res.json(g.messages);
});

// --- Group E2E key distribution ---
app.post('/groups/:groupId/key/:memberFipId', (req, res) => {
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

// --- Pulse AI (proxies to Claude API, key stays on server) ---
app.post('/ai/chat', async (req, res) => {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return res.status(503).json({ error: 'Pulse AI henüz yapılandırılmadı.' });

  const { messages } = req.body;
  if (!Array.isArray(messages) || messages.length === 0)
    return res.status(400).json({ error: 'Mesaj listesi gerekli.' });

  try {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
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

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Photon Chat server running on port ${PORT}`));
