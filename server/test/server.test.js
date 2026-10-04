const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { createApp, resetStore } = require('../index');

let server;
let base;

before(async () => {
  server = createApp().listen(0);
  await new Promise(r => server.once('listening', r));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());
beforeEach(() => resetStore());

async function call(method, path, body, token, userToken) {
  const headers = body ? { 'Content-Type': 'application/json' } : {};
  if (token) headers['x-group-token'] = token;
  if (userToken) headers['x-user-token'] = userToken;
  const res = await fetch(base + path, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = undefined; }
  return { status: res.status, json };
}

const A = 'fip_aaaaaaaaaaaaaaaa';
const B = 'fip_bbbbbbbbbbbbbbbb';
const C = 'fip_cccccccccccccccc';
const key = [A, B].sort().join('__');

test('health endpoint', async () => {
  const r = await call('GET', '/health');
  assert.equal(r.status, 200);
  assert.equal(r.json.app, 'photon-chat');
});

test('presence + lookup returns public key', async () => {
  assert.equal((await call('POST', '/presence', { fipId: A, code: '12345', name: 'Ali', publicKey: 'PK', serverUrl: base })).status, 200);
  const r = await call('GET', '/lookup/12345');
  assert.equal(r.status, 200);
  assert.deepEqual(r.json, { fipId: A, code: '12345', name: 'Ali', publicKey: 'PK', serverUrl: base });
  assert.equal((await call('GET', '/lookup/99999')).status, 404);
});

test('presence rejects invalid input', async () => {
  assert.equal((await call('POST', '/presence', {})).status, 400);
  assert.equal((await call('POST', '/presence', { fipId: 5 })).status, 400);
});

test('malformed JSON gets a 400, not a crash', async () => {
  const res = await fetch(base + '/presence', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{bad' });
  assert.equal(res.status, 400);
});

test('friend request -> accept flow is visible to the requester', async () => {
  // A, B'ye istek gönderir (B'nin sunucusuna)
  await call('POST', `/requests/${B}`, { fromFipId: A, fromCode: '11111', fromName: 'Ali', fromServerUrl: base });
  let r = await call('GET', `/requests/${B}`);
  assert.equal(r.json.length, 1);
  // Aynı istek tekrar gönderilirse çoğalmaz
  await call('POST', `/requests/${B}`, { fromFipId: A, fromCode: '11111', fromName: 'Ali2', fromServerUrl: base });
  r = await call('GET', `/requests/${B}`);
  assert.equal(r.json.length, 1);
  assert.equal(r.json[0].fromName, 'Ali2');

  // B kabul eder: kendi sunucusunda + A'nın sunucusunda
  await call('POST', '/accept', { myFipId: B, otherFipId: A });
  await call('POST', '/accept', { myFipId: A, otherFipId: B });
  assert.equal((await call('GET', `/requests/${B}`)).json.length, 0);
  assert.deepEqual((await call('GET', `/accepted/${A}`)).json, [B]);
});

test('declining removes the request permanently', async () => {
  await call('POST', `/requests/${B}`, { fromFipId: A });
  await call('DELETE', `/requests/${B}/${A}`);
  assert.deepEqual((await call('GET', `/requests/${B}`)).json, []);
});

test('cannot send a friend request to yourself', async () => {
  assert.equal((await call('POST', `/requests/${A}`, { fromFipId: A })).status, 400);
});

test('status distinguishes active, deactivated and unknown', async () => {
  await call('POST', '/presence', { fipId: A, code: '11111' }, null, 'tA');
  await call('POST', '/presence', { fipId: B, code: '22222' }, null, 'tB');
  await call('POST', '/deactivate', { fipId: B }, null, 'tB');
  const r = await call('POST', '/status', { fipIds: [A, B, C] });
  assert.deepEqual(r.json, { active: [A], deactivated: [B] });
  // Eski /active uç noktası hâlâ çalışır
  assert.deepEqual((await call('POST', '/active', { fipIds: [A, B, C] })).json, [A]);
  // Tekrar presence gönderen kullanıcı yeniden aktif olur
  await call('POST', '/presence', { fipId: B, code: '22222' }, null, 'tB2');
  assert.deepEqual((await call('POST', '/status', { fipIds: [B] })).json, { active: [B], deactivated: [] });
});

test('chat messages: store, validate, dedupe, order, delete', async () => {
  assert.equal((await call('POST', `/chat/${key}`, { from: A, text: 'selam', ts: 2 })).status, 200);
  assert.equal((await call('POST', `/chat/${key}`, { from: B, text: 'merhaba', ts: 1 })).status, 200);
  // Retry ile aynı mesaj tekrar gelirse çoğalmaz
  assert.equal((await call('POST', `/chat/${key}`, { from: A, text: 'selam', ts: 2 })).status, 200);
  // Sohbette olmayan biri yazamaz
  assert.equal((await call('POST', `/chat/${key}`, { from: C, text: 'x', ts: 3 })).status, 403);
  // Geçersiz gövde
  assert.equal((await call('POST', `/chat/${key}`, { from: A, text: '', ts: 3 })).status, 400);
  assert.equal((await call('POST', `/chat/${key}`, { from: A, text: 'x' })).status, 400);

  const r = await call('GET', `/chat/${key}`);
  assert.deepEqual(r.json.map(m => m.text), ['merhaba', 'selam']);

  // Taraflardan biri olmayan silemez
  assert.equal((await call('DELETE', `/chat/${key}`)).status, 403);
  await call('POST', '/presence', { fipId: A, code: '11111' }, null, 'tA');
  assert.equal((await call('DELETE', `/chat/${key}`, undefined, null, 'yanlis')).status, 403);
  assert.equal((await call('DELETE', `/chat/${key}`, undefined, null, 'tA')).status, 200);
  assert.deepEqual((await call('GET', `/chat/${key}`)).json, []);
});

test('chat history is capped at 200 messages', async () => {
  for (let i = 1; i <= 205; i++) await call('POST', `/chat/${key}`, { from: A, text: `m${i}`, ts: i });
  const r = await call('GET', `/chat/${key}`);
  assert.equal(r.json.length, 200);
  assert.equal(r.json[0].text, 'm6');
});

test('typing indicator expires', async () => {
  await call('POST', `/typing/${key}`, { fipId: A });
  const r = await call('GET', `/typing/${key}`);
  assert.equal(r.json.length, 1);
  assert.equal(r.json[0].fipId, A);
  await call('POST', `/typing/${key}`, { fipId: A, stop: true });
  assert.deepEqual((await call('GET', `/typing/${key}`)).json, []);
});

test('deactivate wipes user data, chats and owned groups', async () => {
  await call('POST', '/presence', { fipId: A, code: '11111', serverUrl: base }, null, 'tA');
  await call('POST', '/registry/register', { code: '11111', serverUrl: base });
  await call('POST', `/chat/${key}`, { from: A, text: 'x', ts: 1 });
  const g = (await call('POST', '/groups', { ownerFipId: A, ownerName: 'Ali', name: 'G', ownerServerUrl: base })).json;
  await call('POST', '/deactivate', { fipId: A }, null, 'tA');
  assert.deepEqual((await call('GET', `/chat/${key}`)).json, []);
  assert.equal((await call('GET', '/lookup/11111')).status, 404);
  assert.equal((await call('GET', '/registry/lookup/11111')).status, 404);
  assert.equal((await call('GET', `/groups/${g.groupId}/messages`, undefined, g.token)).status, 404);
});

async function makeGroupWithMember() {
  const g = (await call('POST', '/groups', { ownerFipId: A, ownerName: 'Ali', name: 'Takım', ownerServerUrl: base })).json;
  const jr = await call('POST', `/groups/${g.groupId}/join-requests`, { fromFipId: B, fromName: 'Bora', fromServerUrl: base });
  assert.equal(jr.status, 200);
  assert.equal((await call('POST', `/groups/${g.groupId}/members`, { fipId: B }, g.token)).status, 200);
  return { g, ownerToken: g.token, memberToken: jr.json.token };
}

test('group lifecycle: join, accept, message, mute, kick', async () => {
  const g = (await call('POST', '/groups', { ownerFipId: A, ownerName: 'Ali', name: 'Takım', ownerServerUrl: base })).json;
  assert.match(g.groupCode, /^\d{7}$/);
  assert.ok(g.token);
  assert.equal((await call('GET', `/groups/by-code/${g.groupCode}`)).json.groupId, g.groupId);
  assert.equal((await call('GET', `/groups/by-code/${g.groupCode}`)).json.token, undefined, 'token sızmamalı');

  const jr = await call('POST', `/groups/${g.groupId}/join-requests`, { fromFipId: B, fromName: 'Bora', fromServerUrl: base });
  const bt = jr.json.token;
  assert.ok(bt);
  // İkinci istek token vermez (başkası adına token alınamaz)
  const again = await call('POST', `/groups/${g.groupId}/join-requests`, { fromFipId: B, fromName: 'Sahte' });
  assert.equal(again.status, 409);
  assert.equal(again.json.token, undefined);
  const reqs = (await call('GET', `/groups/${g.groupId}/join-requests`)).json;
  assert.equal(reqs.length, 1);
  assert.equal(reqs[0].token, undefined, 'istek listesinde token görünmemeli');

  // Onaylanmadan mesaj gönderemez / okuyamaz
  assert.equal((await call('POST', `/groups/${g.groupId}/messages`, { text: 'hi', ts: 1 }, bt)).status, 403);
  assert.equal((await call('GET', `/groups/${g.groupId}/messages`, undefined, bt)).status, 403);

  await call('POST', `/groups/${g.groupId}/members`, { fipId: B }, g.token);
  assert.equal((await call('GET', `/groups/${g.groupId}/join-requests`)).json.length, 0);
  const members = (await call('GET', `/groups/${g.groupId}/members`)).json;
  assert.deepEqual(members.members.map(m => m.fipId), [A, B]);
  assert.ok(members.members.every(m => m.token === undefined), 'üye listesinde token görünmemeli');
  assert.equal(members.ownerFipId, A);

  assert.equal((await call('POST', `/groups/${g.groupId}/messages`, { fromName: 'Bora', text: 'hi', ts: 1 }, bt)).status, 200);

  await call('POST', `/groups/${g.groupId}/muted`, { fipId: B }, g.token);
  let r = await call('POST', `/groups/${g.groupId}/messages`, { fromName: 'Bora', text: 'hi2', ts: 2 }, bt);
  assert.equal(r.status, 403);
  assert.ok(r.json.error);
  // Sahip susturulamaz / atılamaz
  assert.equal((await call('POST', `/groups/${g.groupId}/muted`, { fipId: A }, g.token)).status, 400);
  assert.equal((await call('DELETE', `/groups/${g.groupId}/members/${A}`, undefined, g.token)).status, 400);

  await call('DELETE', `/groups/${g.groupId}/muted/${B}`, undefined, g.token);
  assert.equal((await call('POST', `/groups/${g.groupId}/messages`, { text: 'hi3', ts: 3 }, bt)).status, 200);

  await call('DELETE', `/groups/${g.groupId}/members/${B}`, undefined, g.token);
  assert.equal((await call('POST', `/groups/${g.groupId}/messages`, { text: 'hi4', ts: 4 }, bt)).status, 403);

  const msgs = (await call('GET', `/groups/${g.groupId}/messages`, undefined, g.token)).json;
  assert.deepEqual(msgs.map(m => m.text), ['hi', 'hi3']);
  // Atılan üye ve yabancılar mesajları okuyamaz
  assert.equal((await call('GET', `/groups/${g.groupId}/messages`, undefined, bt)).status, 403);
  assert.equal((await call('GET', `/groups/${g.groupId}/messages`)).status, 403);
});

test('group security: no self-approval, impersonation or unauthorized admin actions', async () => {
  const { g, ownerToken, memberToken } = await makeGroupWithMember();
  // C, onay beklemeden kendini üye ekleyemez
  assert.equal((await call('POST', `/groups/${g.groupId}/members`, { fipId: C, name: 'Can' })).status, 403);
  // Üye, sahip yetkisi kullanamaz
  assert.equal((await call('POST', `/groups/${g.groupId}/members`, { fipId: C }, memberToken)).status, 403);
  assert.equal((await call('POST', `/groups/${g.groupId}/muted`, { fipId: A }, memberToken)).status, 403);
  assert.equal((await call('DELETE', `/groups/${g.groupId}`, undefined, memberToken)).status, 403);
  assert.equal((await call('DELETE', `/groups/${g.groupId}?ownerFipId=${A}`)).status, 403, 'eski fipId tabanlı silme kapalı');
  // Kimse başkasını gruptan çıkaramaz (sahip hariç)
  assert.equal((await call('DELETE', `/groups/${g.groupId}/members/${B}`)).status, 403);
  // Gönderen token'dan belirlenir: B, A adına yazamaz
  await call('POST', `/groups/${g.groupId}/messages`, { from: A, fromName: 'Ali', text: 'sahte', ts: 9 }, memberToken);
  const msgs = (await call('GET', `/groups/${g.groupId}/messages`, undefined, ownerToken)).json;
  assert.equal(msgs.at(-1).from, B);
  // Üye kendi isteğiyle ayrılabilir
  assert.equal((await call('DELETE', `/groups/${g.groupId}/members/${B}`, undefined, memberToken)).status, 200);
  assert.equal((await call('GET', `/groups/${g.groupId}/messages`, undefined, memberToken)).status, 403);
});

test('groups allow more than 10 senders', async () => {
  const g = (await call('POST', '/groups', { ownerFipId: A, ownerName: 'Ali', name: 'Büyük', ownerServerUrl: base })).json;
  for (let i = 0; i < 15; i++) {
    const id = `fip_member${String(i).padStart(8, '0')}`;
    const t = (await call('POST', `/groups/${g.groupId}/join-requests`, { fromFipId: id, fromName: `U${i}` })).json.token;
    await call('POST', `/groups/${g.groupId}/members`, { fipId: id }, g.token);
    assert.equal((await call('POST', `/groups/${g.groupId}/messages`, { text: 'x', ts: 100 + i }, t)).status, 200);
  }
});

test('only the owner can delete a group', async () => {
  const { g, ownerToken, memberToken } = await makeGroupWithMember();
  assert.equal((await call('DELETE', `/groups/${g.groupId}`, undefined, memberToken)).status, 403);
  assert.equal((await call('DELETE', `/groups/${g.groupId}`, undefined, ownerToken)).status, 200);
  assert.equal((await call('GET', `/groups/${g.groupId}/members`)).status, 404);
});

test('unknown group returns 404', async () => {
  assert.equal((await call('GET', '/groups/nope/messages')).status, 404);
  assert.equal((await call('GET', '/groups/by-code/0000000')).status, 404);
});

test('bridge registry validates input', async () => {
  assert.equal((await call('POST', '/registry/register', { code: '12345', serverUrl: 'not a url' })).status, 400);
  assert.equal((await call('POST', '/registry/register', { code: '12345', serverUrl: 'https://x.onrender.com' })).status, 200);
  assert.equal((await call('GET', '/registry/lookup/12345')).json.serverUrl, 'https://x.onrender.com');
  // Başka bir sunucu, kodu silemez
  await call('POST', '/registry/unregister', { code: '12345', serverUrl: 'https://evil.example' });
  assert.equal((await call('GET', '/registry/lookup/12345')).status, 200);
  await call('POST', '/registry/unregister', { code: '12345', serverUrl: 'https://x.onrender.com' });
  assert.equal((await call('GET', '/registry/lookup/12345')).status, 404);
});

test('pulse AI without key reports 503', async () => {
  const saved = process.env.ANTHROPIC_API_KEY;
  delete process.env.ANTHROPIC_API_KEY;
  const r = await call('POST', '/ai/chat', { messages: [{ role: 'user', content: 'selam' }] });
  assert.equal(r.status, 503);
  if (saved !== undefined) process.env.ANTHROPIC_API_KEY = saved;
});

test('pulse AI validates history before calling upstream', async () => {
  const saved = process.env.ANTHROPIC_API_KEY;
  process.env.ANTHROPIC_API_KEY = 'test';
  assert.equal((await call('POST', '/ai/chat', { messages: [] })).status, 400);
  assert.equal((await call('POST', '/ai/chat', { messages: [{ role: 'assistant', content: 'x' }] })).status, 400);
  if (saved !== undefined) process.env.ANTHROPIC_API_KEY = saved; else delete process.env.ANTHROPIC_API_KEY;
});

test('pulse AI is rate limited per client', async () => {
  const saved = process.env.ANTHROPIC_API_KEY;
  process.env.ANTHROPIC_API_KEY = 'test';
  let last;
  // Geçersiz geçmiş upstream'e gitmeden 400 döner ama hız sınırına sayılır
  for (let i = 0; i < 31; i++) last = await call('POST', '/ai/chat', { messages: [] });
  assert.equal(last.status, 429);
  if (saved !== undefined) process.env.ANTHROPIC_API_KEY = saved; else delete process.env.ANTHROPIC_API_KEY;
});

test('user security: nobody can hijack presence, swap keys or deactivate others', async () => {
  await call('POST', '/presence', { fipId: A, code: '11111', name: 'Ali', publicKey: 'PK_ALI' }, null, 'gizli');
  // Saldırgan Ali'nin adını / public key'ini değiştiremez (E2E MITM engeli)
  assert.equal((await call('POST', '/presence', { fipId: A, code: '11111', name: 'Sahte', publicKey: 'PK_EVIL' })).status, 403);
  assert.equal((await call('POST', '/presence', { fipId: A, code: '11111', name: 'Sahte', publicKey: 'PK_EVIL' }, null, 'baska')).status, 403);
  assert.equal((await call('GET', '/lookup/11111')).json.publicKey, 'PK_ALI');
  // Saldırgan Ali'yi "hesabını sildi" gösteremez
  assert.equal((await call('POST', '/deactivate', { fipId: A })).status, 403);
  assert.equal((await call('POST', '/deactivate', { fipId: A }, null, 'baska')).status, 403);
  assert.deepEqual((await call('POST', '/status', { fipIds: [A] })).json, { active: [A], deactivated: [] });
  // Kayıtsız kullanıcı silinemez (sunucu yeniden başladıktan sonra yarış)
  assert.equal((await call('POST', '/deactivate', { fipId: C }, null, 'x')).status, 404);
  // Sahibi kendi token'ıyla güncelleyebilir ve silebilir
  assert.equal((await call('POST', '/presence', { fipId: A, code: '11111', name: 'Ali2', publicKey: 'PK_ALI' }, null, 'gizli')).status, 200);
  assert.equal((await call('POST', '/deactivate', { fipId: A }, null, 'gizli')).status, 200);
  // Token özeti hiçbir yanıtta görünmez
  await call('POST', '/presence', { fipId: B, code: '22222' }, null, 'tb');
  assert.equal(JSON.stringify((await call('GET', '/lookup/22222')).json).includes('token'), false);
});

test('group E2E key distribution: owner wraps, only the member can fetch, server never sees plaintext key', async () => {
  const g = (await call('POST', '/groups', { ownerFipId: A, ownerName: 'Ali', name: 'G', ownerServerUrl: base, ownerPublicKey: 'PK_A' })).json;
  assert.equal(g.ownerPublicKey, 'PK_A');
  assert.equal((await call('GET', `/groups/by-code/${g.groupCode}`)).json.ownerPublicKey, 'PK_A');
  const bt = (await call('POST', `/groups/${g.groupId}/join-requests`, { fromFipId: B, fromName: 'Bora', fromPublicKey: 'PK_B' })).json.token;
  const ct = (await call('POST', `/groups/${g.groupId}/join-requests`, { fromFipId: C, fromName: 'Can', fromPublicKey: 'PK_C' })).json.token;
  assert.equal((await call('GET', `/groups/${g.groupId}/join-requests`)).json[0].fromPublicKey, 'PK_B');
  await call('POST', `/groups/${g.groupId}/members`, { fipId: B }, g.token);
  await call('POST', `/groups/${g.groupId}/members`, { fipId: C }, g.token);

  let info = (await call('GET', `/groups/${g.groupId}/members`)).json;
  assert.equal(info.ownerPublicKey, 'PK_A');
  assert.equal(info.members.find(m => m.fipId === B).publicKey, 'PK_B');
  assert.equal(info.members.find(m => m.fipId === B).keyId, null);

  // Yalnızca sahip anahtar koyabilir
  assert.equal((await call('POST', `/groups/${g.groupId}/key/${B}`, { encryptedKey: 'WRAP', keyId: 'k1' }, bt)).status, 403);
  assert.equal((await call('POST', `/groups/${g.groupId}/key/${B}`, { encryptedKey: 'WRAP_B', keyId: 'k1' }, g.token)).status, 200);
  assert.equal((await call('POST', `/groups/${g.groupId}/key/fip_yok`, { encryptedKey: 'X', keyId: 'k1' }, g.token)).status, 404);
  info = (await call('GET', `/groups/${g.groupId}/members`)).json;
  assert.equal(info.members.find(m => m.fipId === B).keyId, 'k1');
  assert.equal(JSON.stringify(info).includes('WRAP'), false, 'sarılmış anahtar listede görünmez');

  // Yalnızca ilgili üye kendi anahtarını alabilir
  assert.deepEqual((await call('GET', `/groups/${g.groupId}/key/${B}`, undefined, bt)).json, { encryptedKey: 'WRAP_B', keyId: 'k1' });
  assert.equal((await call('GET', `/groups/${g.groupId}/key/${B}`, undefined, ct)).status, 403);
  assert.equal((await call('GET', `/groups/${g.groupId}/key/${B}`)).status, 403);

  // Atılan üyenin anahtar kaydı silinir
  await call('DELETE', `/groups/${g.groupId}/members/${B}`, undefined, g.token);
  assert.equal((await call('GET', `/groups/${g.groupId}/key/${B}`, undefined, bt)).status, 403);
});
