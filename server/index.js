const express = require('express');

// --- Limits ---
const MAX_CHAT_MESSAGES = 200;
const MAX_GROUP_MESSAGES = 500;
const MAX_TEXT_LENGTH = 16 * 1024; // E2E base64 metni düz metinden uzundur
const MAX_REQUESTS_PER_USER = 100;
const TYPING_TTL_MS = 4000;
const AI_MAX_HISTORY = 20;
const AI_MAX_CONTENT = 4000;
const AI_RATE_WINDOW_MS = 5 * 60 * 1000;
const AI_RATE_MAX = Number(process.env.PULSE_AI_RATE_LIMIT) || 30; // IP başına 5 dakikada en fazla istek

// --- In-memory store ---
const users = new Map();       // fipId -> {code, name, publicKey, serverUrl, ts}
const deactivated = new Set(); // hesabını silmiş fipId'ler
const requests = new Map();    // toFipId -> [{fromFipId, ...}]
const accepted = new Map();    // fipId -> Set(otherFipId)
const chats = new Map();       // chatKey -> [{from, text, ts}]
const groups = new Map();
const typingMap = new Map();   // chatKey -> [{fipId, ts}]
const registry = new Map();    // code -> serverUrl (bridge: global code directory)
const aiHits = new Map();      // ip -> [ts] (Pulse AI hız sınırı)

function rand(n) {
  return Math.floor(Math.random() * Math.pow(10, n)).toString().padStart(n, '0');
}

const isStr = (v, max = 256) => typeof v === 'string' && v.length > 0 && v.length <= max;
const optStr = (v, max = 256) => v === undefined || v === null || (typeof v === 'string' && v.length <= max);
const isUrl = (v) => isStr(v, 512) && /^https?:\/\/\S+$/i.test(v);
const isTs = (v) => Number.isSafeInteger(v) && v > 0;

function uniqueGroupCode() {
  const used = new Set([...groups.values()].map(g => g.groupCode));
  let code;
  do { code = rand(7); } while (used.has(code));
  return code;
}

function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1); // Render vb. ters proxy arkasında gerçek istemci IP'si
  app.use(express.json({ limit: '128kb' }));

  // --- Health ---
  app.get(['/', '/health'], (req, res) => {
    res.json({ app: 'photon-chat', ok: true });
  });

  // --- Presence ---
  app.post('/presence', (req, res) => {
    const { fipId, code, name, publicKey, serverUrl } = req.body || {};
    if (!isStr(fipId, 128) || !optStr(code, 16) || !optStr(name, 64) || !optStr(publicKey, 256) || !optStr(serverUrl, 512))
      return res.sendStatus(400);
    users.set(fipId, { code, name, publicKey, serverUrl, ts: Date.now() });
    deactivated.delete(fipId);
    res.sendStatus(200);
  });

  app.get('/lookup/:code', (req, res) => {
    for (const [fipId, u] of users) {
      if (u.code === req.params.code) {
        return res.json({ fipId, code: u.code, name: u.name, publicKey: u.publicKey, serverUrl: u.serverUrl });
      }
    }
    res.sendStatus(404);
  });

  // --- Friend requests ---
  app.post('/requests/:toFipId', (req, res) => {
    const { toFipId } = req.params;
    const { fromFipId, fromCode, fromName, fromServerUrl, fromPublicKey } = req.body || {};
    if (!isStr(fromFipId, 128) || !optStr(fromCode, 16) || !optStr(fromName, 64) || !optStr(fromServerUrl, 512) || !optStr(fromPublicKey, 256))
      return res.sendStatus(400);
    if (fromFipId === toFipId) return res.sendStatus(400);
    if (!requests.has(toFipId)) requests.set(toFipId, []);
    const list = requests.get(toFipId);
    const entry = { fromFipId, fromCode, fromName, fromServerUrl, fromPublicKey, ts: Date.now() };
    const idx = list.findIndex(r => r.fromFipId === fromFipId);
    if (idx === -1) {
      list.push(entry);
      if (list.length > MAX_REQUESTS_PER_USER) list.splice(0, list.length - MAX_REQUESTS_PER_USER);
    } else {
      list[idx] = entry; // güncel isim / anahtar
    }
    res.sendStatus(200);
  });

  app.get('/requests/:toFipId', (req, res) => {
    res.json(requests.get(req.params.toFipId) || []);
  });

  // İsteği reddet: listeden kaldırır, böylece bir sonraki senkronda geri gelmez.
  app.delete('/requests/:toFipId/:fromFipId', (req, res) => {
    const list = requests.get(req.params.toFipId);
    if (list) {
      const rest = list.filter(r => r.fromFipId !== req.params.fromFipId);
      if (rest.length) requests.set(req.params.toFipId, rest);
      else requests.delete(req.params.toFipId);
    }
    res.sendStatus(200);
  });

  // myFipId'nin kabul listesine otherFipId eklenir ve otherFipId'den gelen istek silinir.
  // İstemci bunu hem kendi sunucusunda hem de isteği gönderenin sunucusunda çağırır.
  app.post('/accept', (req, res) => {
    const { myFipId, otherFipId } = req.body || {};
    if (!isStr(myFipId, 128) || !isStr(otherFipId, 128)) return res.sendStatus(400);
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
    const { fipIds } = req.body || {};
    if (!Array.isArray(fipIds)) return res.json([]);
    res.json(fipIds.filter(id => users.has(id)));
  });

  // Ayrıntılı durum: aktif (kayıtlı) ve hesabını silmiş kullanıcılar.
  // Sunucu yeniden başladığında herkes "bilinmiyor" görünür; istemci bu durumda kişiyi silmez.
  app.post('/status', (req, res) => {
    const { fipIds } = req.body || {};
    if (!Array.isArray(fipIds)) return res.sendStatus(400);
    const ids = fipIds.filter(id => typeof id === 'string').slice(0, 500);
    res.json({
      active: ids.filter(id => users.has(id)),
      deactivated: ids.filter(id => deactivated.has(id)),
    });
  });

  // --- Direct messages ---
  app.get('/chat/:chatKey', (req, res) => {
    res.json(chats.get(req.params.chatKey) || []);
  });

  app.post('/chat/:chatKey', (req, res) => {
    const { from, text, ts } = req.body || {};
    if (!isStr(from, 128) || !isStr(text, MAX_TEXT_LENGTH) || !isTs(ts)) return res.sendStatus(400);
    const key = req.params.chatKey;
    if (!key.split('__').includes(from)) return res.sendStatus(403);
    if (!chats.has(key)) chats.set(key, []);
    const msgs = chats.get(key);
    // Aynı mesajın tekrar gönderilmesini (retry) yok say
    if (!msgs.some(m => m.from === from && m.ts === ts)) {
      msgs.push({ from, text, ts });
      msgs.sort((a, b) => a.ts - b.ts);
      if (msgs.length > MAX_CHAT_MESSAGES) msgs.splice(0, msgs.length - MAX_CHAT_MESSAGES);
    }
    res.sendStatus(200);
  });

  app.delete('/chat/:chatKey', (req, res) => {
    chats.delete(req.params.chatKey);
    res.sendStatus(200);
  });

  // --- Typing indicator ---
  app.post('/typing/:chatKey', (req, res) => {
    const { fipId, stop } = req.body || {};
    if (!isStr(fipId, 128)) return res.sendStatus(400);
    const key = req.params.chatKey;
    if (stop === true) {
      // Mesaj gönderildi: "yazıyor" göstergesini hemen kapat
      const rest = (typingMap.get(key) || []).filter(t => t.fipId !== fipId);
      if (rest.length) typingMap.set(key, rest); else typingMap.delete(key);
      return res.sendStatus(200);
    }
    if (!typingMap.has(key)) typingMap.set(key, []);
    const list = typingMap.get(key);
    const idx = list.findIndex(t => t.fipId === fipId);
    // Sunucu saatini kullan: istemci saatleri farklı olabilir.
    const entry = { fipId, ts: Date.now() };
    if (idx === -1) list.push(entry);
    else list[idx] = entry;
    res.sendStatus(200);
  });

  app.get('/typing/:chatKey', (req, res) => {
    const now = Date.now();
    const list = typingMap.get(req.params.chatKey) || [];
    res.json(list.filter(t => now - t.ts < TYPING_TTL_MS));
  });

  // --- Deactivate ---
  app.post('/deactivate', (req, res) => {
    const { fipId } = req.body || {};
    if (!isStr(fipId, 128)) return res.sendStatus(400);
    const u = users.get(fipId);
    if (u && u.code && registry.get(u.code) === u.serverUrl) registry.delete(u.code);
    users.delete(fipId);
    deactivated.add(fipId);
    requests.delete(fipId);
    accepted.delete(fipId);
    for (const key of [...chats.keys()]) {
      if (key.split('__').includes(fipId)) chats.delete(key);
    }
    for (const key of [...typingMap.keys()]) {
      if (key.split('__').includes(fipId)) typingMap.delete(key);
    }
    for (const [groupId, g] of groups) {
      if (g.ownerFipId === fipId) { groups.delete(groupId); continue; }
      g.members = g.members.filter(m => m.fipId !== fipId);
      g.joinRequests = g.joinRequests.filter(r => r.fromFipId !== fipId);
      g.muted = g.muted.filter(id => id !== fipId);
    }
    res.sendStatus(200);
  });

  // --- Groups ---
  app.post('/groups', (req, res) => {
    const { ownerFipId, ownerName, name, ownerServerUrl } = req.body || {};
    if (!isStr(ownerFipId, 128) || !isStr(name, 64) || !optStr(ownerName, 64) || !optStr(ownerServerUrl, 512))
      return res.sendStatus(400);
    const groupId = `grp_${Date.now()}_${Math.random().toString(36).slice(2)}`;
    const groupCode = uniqueGroupCode();
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

  // :groupId parametresi olan tüm rotalar için grubu yükle
  app.param('groupId', (req, res, next, id) => {
    const g = groups.get(id);
    if (!g) return res.sendStatus(404);
    req.group = g;
    next();
  });

  // Grubu sil (yalnızca sahip)
  app.delete('/groups/:groupId', (req, res) => {
    const g = req.group;
    if (req.query.ownerFipId !== g.ownerFipId) return res.sendStatus(403);
    groups.delete(g.groupId);
    res.sendStatus(200);
  });

  app.post('/groups/:groupId/join-requests', (req, res) => {
    const g = req.group;
    const { fromFipId, fromName, fromServerUrl } = req.body || {};
    if (!isStr(fromFipId, 128) || !optStr(fromName, 64) || !optStr(fromServerUrl, 512)) return res.sendStatus(400);
    if (g.members.some(m => m.fipId === fromFipId)) return res.sendStatus(200); // zaten üye
    if (!g.joinRequests.find(r => r.fromFipId === fromFipId))
      g.joinRequests.push({ fromFipId, fromName, fromServerUrl, ts: Date.now() });
    res.sendStatus(200);
  });

  app.get('/groups/:groupId/join-requests', (req, res) => {
    res.json(req.group.joinRequests);
  });

  app.delete('/groups/:groupId/join-requests/:fipId', (req, res) => {
    const g = req.group;
    g.joinRequests = g.joinRequests.filter(r => r.fromFipId !== req.params.fipId);
    res.sendStatus(200);
  });

  app.get('/groups/:groupId/members', (req, res) => {
    const g = req.group;
    res.json({ members: g.members, muted: g.muted, ownerFipId: g.ownerFipId, name: g.name });
  });

  app.post('/groups/:groupId/members', (req, res) => {
    const g = req.group;
    const { fipId, name, serverUrl } = req.body || {};
    if (!isStr(fipId, 128) || !optStr(name, 64) || !optStr(serverUrl, 512)) return res.sendStatus(400);
    if (!g.members.find(m => m.fipId === fipId)) g.members.push({ fipId, name, serverUrl });
    g.joinRequests = g.joinRequests.filter(r => r.fromFipId !== fipId);
    res.sendStatus(200);
  });

  app.delete('/groups/:groupId/members/:fipId', (req, res) => {
    const g = req.group;
    if (req.params.fipId === g.ownerFipId) return res.sendStatus(400); // sahip atılamaz
    g.members = g.members.filter(m => m.fipId !== req.params.fipId);
    // Susturma listesinden de çıkar
    g.muted = g.muted.filter(id => id !== req.params.fipId);
    delete g.groupKeys[req.params.fipId];
    res.sendStatus(200);
  });

  // --- Group mute ---
  app.post('/groups/:groupId/muted', (req, res) => {
    const g = req.group;
    const { fipId } = req.body || {};
    if (!isStr(fipId, 128)) return res.sendStatus(400);
    if (fipId === g.ownerFipId) return res.sendStatus(400);
    if (!g.muted.includes(fipId)) g.muted.push(fipId);
    res.sendStatus(200);
  });

  app.delete('/groups/:groupId/muted/:fipId', (req, res) => {
    const g = req.group;
    g.muted = g.muted.filter(id => id !== req.params.fipId);
    res.sendStatus(200);
  });

  app.get('/groups/:groupId/muted', (req, res) => {
    res.json(req.group.muted);
  });

  // --- Group messages ---
  app.post('/groups/:groupId/messages', (req, res) => {
    const g = req.group;
    const { from, fromName, text, ts } = req.body || {};
    if (!isStr(from, 128) || !optStr(fromName, 64) || !isStr(text, MAX_TEXT_LENGTH)) return res.sendStatus(400);
    if (!g.members.some(m => m.fipId === from)) {
      return res.status(403).json({ error: 'Bu grubun üyesi değilsin (katılma isteğin onay bekliyor olabilir).' });
    }
    // Susturulan kullanıcı mesaj gönderemez
    if (g.muted.includes(from)) {
      return res.status(403).json({ error: 'Grup yöneticisi seni susturdu.' });
    }
    const msgTs = isTs(ts) ? ts : Date.now();
    if (!g.messages.some(m => m.from === from && m.ts === msgTs)) {
      g.messages.push({ from, fromName, text, ts: msgTs });
      if (g.messages.length > MAX_GROUP_MESSAGES) g.messages.splice(0, g.messages.length - MAX_GROUP_MESSAGES);
    }
    res.sendStatus(200);
  });

  // Mesajları yalnızca grubun güncel üyeleri okuyabilir (atılan / onay bekleyen kişiler göremez).
  app.get('/groups/:groupId/messages', (req, res) => {
    const g = req.group;
    if (!g.members.some(m => m.fipId === req.query.fipId)) {
      return res.status(403).json({ error: 'Bu grubun üyesi değilsin.' });
    }
    res.json(g.messages);
  });

  // --- Group E2E key distribution ---
  app.post('/groups/:groupId/key/:memberFipId', (req, res) => {
    const g = req.group;
    const { encryptedKey } = req.body || {};
    if (!isStr(encryptedKey, 1024)) return res.sendStatus(400);
    g.groupKeys[req.params.memberFipId] = encryptedKey;
    res.sendStatus(200);
  });

  app.get('/groups/:groupId/key/:memberFipId', (req, res) => {
    const key = req.group.groupKeys[req.params.memberFipId];
    if (!key) return res.sendStatus(404);
    res.json({ encryptedKey: key });
  });

  // --- Bridge registry (global code -> serverUrl directory) ---
  app.post('/registry/register', (req, res) => {
    const { code, serverUrl } = req.body || {};
    if (!isStr(code, 16) || !isUrl(serverUrl)) return res.sendStatus(400);
    registry.set(code, serverUrl);
    res.sendStatus(200);
  });

  app.post('/registry/unregister', (req, res) => {
    const { code, serverUrl } = req.body || {};
    if (!isStr(code, 16)) return res.sendStatus(400);
    if (registry.get(code) === serverUrl) registry.delete(code);
    res.sendStatus(200);
  });

  app.get('/registry/lookup/:code', (req, res) => {
    const serverUrl = registry.get(req.params.code);
    if (!serverUrl) return res.sendStatus(404);
    res.json({ serverUrl });
  });

  // --- Pulse AI (proxies to Claude API, key stays on server) ---
  app.post('/ai/chat', async (req, res) => {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) return res.status(503).json({ error: 'Pulse AI henüz yapılandırılmadı.' });

    // API anahtarının maliyetini korumak için basit hız sınırı
    const now = Date.now();
    const hits = (aiHits.get(req.ip) || []).filter(t => now - t < AI_RATE_WINDOW_MS);
    if (hits.length >= AI_RATE_MAX) {
      aiHits.set(req.ip, hits);
      return res.status(429).json({ error: 'Çok fazla istek gönderdin. Birkaç dakika sonra tekrar dene.' });
    }
    hits.push(now);
    aiHits.set(req.ip, hits);

    const { messages } = req.body || {};
    if (!Array.isArray(messages) || messages.length === 0)
      return res.status(400).json({ error: 'Mesaj listesi gerekli.' });

    // Geçerli mesajları al, son N mesajla sınırla, user ile başlamasını ve rollerin sırayla gelmesini sağla
    let history = messages
      .filter(m => m && (m.role === 'user' || m.role === 'assistant') && isStr(m.content, AI_MAX_CONTENT))
      .slice(-AI_MAX_HISTORY)
      .map(m => ({ role: m.role, content: m.content }));
    while (history.length && history[0].role !== 'user') history.shift();
    history = history.reduce((acc, m) => {
      const last = acc[acc.length - 1];
      if (last && last.role === m.role) last.content += '\n\n' + m.content;
      else acc.push({ ...m });
      return acc;
    }, []);
    if (!history.length || history[history.length - 1].role !== 'user')
      return res.status(400).json({ error: 'Son mesaj kullanıcıdan olmalı.' });

    try {
      const response = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify({
          model: process.env.PULSE_AI_MODEL || 'claude-haiku-4-5-20251001',
          max_tokens: 1024,
          system: 'Sen Pulse AI\'sin — Photon Chat uygulamasının kişisel yapay zeka asistanısın. Kullanıcıya Türkçe yardım et. Kelime anlamları, genel sorular, sohbet — her konuda kısa ve samimi cevaplar ver. Asla görsel, dosya veya bağlantı paylaşma.',
          messages: history,
        }),
        signal: AbortSignal.timeout(25000),
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        console.error('Pulse AI error', response.status, data && data.error);
        return res.status(502).json({ error: 'AI şu an yanıt veremiyor. Biraz sonra tekrar dene.' });
      }
      const reply = (data.content || []).filter(c => c.type === 'text').map(c => c.text).join('\n').trim();
      if (!reply) return res.status(502).json({ error: 'AI yanıt vermedi.' });
      res.json({ reply });
    } catch (e) {
      res.status(502).json({ error: 'AI bağlantı hatası.' });
    }
  });

  // Bozuk JSON vb. hatalar için düzgün yanıt
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    res.status(err.status || 400).json({ error: 'Geçersiz istek.' });
  });

  return app;
}

// Süresi geçmiş "yazıyor" kayıtlarını temizle (bellek sızıntısını önler)
const cleanup = setInterval(() => {
  const now = Date.now();
  for (const [key, list] of typingMap) {
    const fresh = list.filter(t => now - t.ts < TYPING_TTL_MS);
    if (fresh.length) typingMap.set(key, fresh);
    else typingMap.delete(key);
  }
  for (const [ip, hits] of aiHits) {
    if (!hits.some(t => now - t < AI_RATE_WINDOW_MS)) aiHits.delete(ip);
  }
}, 30000);
cleanup.unref();

function resetStore() {
  for (const m of [users, requests, accepted, chats, groups, typingMap, registry, aiHits]) m.clear();
  deactivated.clear();
}

module.exports = { createApp, resetStore };

if (require.main === module) {
  const PORT = process.env.PORT || 3000;
  createApp().listen(PORT, () => console.log(`Photon Chat server running on port ${PORT}`));
}
