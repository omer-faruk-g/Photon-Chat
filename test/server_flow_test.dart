// Gerçek Node sunucusunu başlatır ve uygulamanın API istemcisiyle (KnkApi)
// iki kullanıcının tüm akışını uçtan uca doğrular.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photon_chat/e2e.dart';
import 'package:photon_chat/fip.dart';
import 'package:photon_chat/knk_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Process _server;
late String base;

Future<SecretKey> _boraSharedKey(SimpleKeyPair bora, String myPub) async {
  final shared = await X25519().sharedSecretKey(
    keyPair: bora,
    remotePublicKey: SimplePublicKey(base64.decode(myPub), type: KeyPairType.x25519),
  );
  return Hkdf(hmac: Hmac(Sha256()), outputLength: 32).deriveKey(
    secretKey: SecretKey(await shared.extractBytes()),
    info: utf8.encode('photon-chat-e2e-v1'),
    nonce: const [],
  );
}

void main() {
  setUpAll(() async {
    final serverDir = '${Directory.current.path}/server';
    if (!File('$serverDir/node_modules/express/package.json').existsSync()) {
      fail('Önce "cd server && npm install" çalıştırın.');
    }
    final port = 40000 + DateTime.now().millisecond;
    _server = await Process.start('node', ['index.js'], workingDirectory: serverDir, environment: {'PORT': '$port'});
    final ready = Completer<void>();
    _server.stdout.transform(utf8.decoder).listen((l) { if (l.contains('running') && !ready.isCompleted) ready.complete(); });
    _server.stderr.transform(utf8.decoder).listen(stderr.write);
    await ready.future.timeout(const Duration(seconds: 10));
    base = 'http://127.0.0.1:$port';
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() => _server.kill());

  test('friend request, accept, E2E chat, typing, status and deactivation', () async {
    final ali = FipBlock.generate();
    final bora = FipBlock.generate();
    final aliPub = await getMyPublicKeyBase64();
    final boraKp = await X25519().newKeyPair();
    final boraPub = base64.encode((await boraKp.extractPublicKey()).bytes);

    expect(await KnkApi.registerPresence(base, ali.fipId, ali.code, 'Ali', publicKey: aliPub), isTrue);
    expect(await KnkApi.registerPresence(base, bora.fipId, bora.code, 'Bora', publicKey: boraPub), isTrue);

    // Ali, Bora'yı kodla bulur ve istek gönderir
    final found = await KnkApi.lookupByCode(base, bora.code);
    expect(found!['fipId'], bora.fipId);
    expect(found['publicKey'], boraPub);
    expect(await KnkApi.sendFriendRequest(toServerUrl: base, toFipId: bora.fipId, fromFipId: ali.fipId,
        fromCode: ali.code, fromName: 'Ali', fromServerUrl: base, fromPublicKey: aliPub), isTrue);

    // Bora isteği görür ve kabul eder
    final incoming = await KnkApi.getIncomingRequests(base, bora.fipId);
    expect(incoming!.single['fromFipId'], ali.fipId);
    expect(incoming.single['fromPublicKey'], aliPub);
    await KnkApi.acceptFriendRequest(myServerUrl: base, myFipId: bora.fipId, otherFipId: ali.fipId, otherServerUrl: base);
    expect(await KnkApi.getIncomingRequests(base, bora.fipId), isEmpty);
    // Ali kabulü kendi sunucusunda görür (eski sürümde hiç görünmüyordu)
    expect(await KnkApi.getAcceptedRequests(base, ali.fipId), contains(bora.fipId));

    // Şifreli mesajlaşma
    final key = chatKeyFor(ali.fipId, bora.fipId);
    final aliKey = await deriveSharedKey(boraPub);
    final boraKey = await _boraSharedKey(boraKp, aliPub);
    final payload = await encryptChatMessage('Gizli selam 🔒', aliKey);
    expect(await KnkApi.sendMessage(receiverServerUrl: base, chatKey: key, from: ali.fipId, text: payload, ts: 1000), isTrue);
    final msgs = await KnkApi.getMessages(key, receiverServerUrl: base);
    expect(msgs!.single['text'], isNot(contains('Gizli')));
    expect(await decryptChatMessage(msgs.single['text'] as String, boraKey), 'Gizli selam 🔒');

    // Yazıyor göstergesi: Bora, Ali'nin sunucusuna yazar; Ali kendi sunucusundan okur
    await KnkApi.sendTyping(base, key, bora.fipId);
    expect((await KnkApi.getTyping(base, key)).map((t) => t['fipId']), contains(bora.fipId));

    // Durum: aktif / bilinmiyor / silinmiş
    expect(await KnkApi.getStatus(base, bora.fipId), ContactStatus.active);
    expect(await KnkApi.getStatus(base, 'fip_yok'), ContactStatus.unknown);
    expect(await KnkApi.getStatus('http://127.0.0.1:1', bora.fipId), ContactStatus.unknown,
        reason: 'ulaşılamayan sunucu kişiyi silinmiş göstermemeli');
    await KnkApi.deactivate(base, bora.fipId);
    expect(await KnkApi.getStatus(base, bora.fipId), ContactStatus.deactivated);
    expect(await KnkApi.getMessages(key, receiverServerUrl: base), isEmpty);
  });

  test('declined requests do not come back', () async {
    final a = FipBlock.generate();
    final b = FipBlock.generate();
    await KnkApi.sendFriendRequest(toServerUrl: base, toFipId: b.fipId, fromFipId: a.fipId,
        fromCode: a.code, fromName: 'A', fromServerUrl: base);
    expect(await KnkApi.getIncomingRequests(base, b.fipId), hasLength(1));
    await KnkApi.declineFriendRequest(myServerUrl: base, myFipId: b.fipId, otherFipId: a.fipId);
    expect(await KnkApi.getIncomingRequests(base, b.fipId), isEmpty);
  });

  test('group flow: create, join, accept, chat, mute, kick, leave, delete', () async {
    final owner = FipBlock.generate();
    final member = FipBlock.generate();
    final g = await KnkApi.createGroup(base, ownerFipId: owner.fipId, ownerName: 'Sahip', name: 'Takım', ownerServerUrl: base);
    final groupId = g!['groupId'] as String;
    final code = g['groupCode'] as String;

    final byCode = await KnkApi.getGroupByCode(base, code);
    expect(byCode!['groupId'], groupId);

    expect(await KnkApi.sendGroupMessage(base, groupId, from: member.fipId, fromName: 'Üye', text: 'x', ts: 1), isNotNull,
        reason: 'üye olmayan yazamaz');

    expect(await KnkApi.sendGroupJoinRequest(base, groupId, fromFipId: member.fipId, fromName: 'Üye', fromServerUrl: base), isTrue);
    expect((await KnkApi.getGroupJoinRequests(base, groupId))!.single['fromFipId'], member.fipId);
    expect(await KnkApi.acceptGroupMember(base, groupId, fipId: member.fipId, name: 'Üye', serverUrl: base), isTrue);

    final info = await KnkApi.getGroupMembers(base, groupId);
    expect((info!['members'] as List).length, 2);

    expect(await KnkApi.sendGroupMessage(base, groupId, from: member.fipId, fromName: 'Üye', text: 'merhaba', ts: 2), isNull);
    expect(await KnkApi.sendGroupMessage(base, groupId, from: owner.fipId, fromName: 'Sahip', text: 'hoş geldin', ts: 3), isNull);
    expect((await KnkApi.getGroupMessages(base, groupId, member.fipId))!.map((m) => m['text']), ['merhaba', 'hoş geldin']);
    expect(await KnkApi.getGroupMessages(base, groupId, 'fip_yabanci'), isEmpty, reason: 'üye olmayan okuyamaz');

    expect(await KnkApi.muteGroupMember(base, groupId, member.fipId), isTrue);
    final muted = await KnkApi.sendGroupMessage(base, groupId, from: member.fipId, fromName: 'Üye', text: 'x', ts: 4);
    expect(muted, contains('sustur'));
    expect(await KnkApi.unmuteGroupMember(base, groupId, member.fipId), isTrue);

    expect(await KnkApi.leaveGroup(base, groupId, member.fipId), isTrue);
    expect(await KnkApi.getGroupMessages(base, groupId, member.fipId), isEmpty, reason: 'ayrılan üye artık okuyamaz');
    expect(await KnkApi.sendGroupMessage(base, groupId, from: member.fipId, fromName: 'Üye', text: 'x', ts: 5), isNotNull);

    expect(await KnkApi.deleteGroup(base, groupId, member.fipId), isFalse, reason: 'sadece sahip silebilir');
    expect(await KnkApi.deleteGroup(base, groupId, owner.fipId), isTrue);
    expect((await KnkApi.getGroupMembers(base, groupId))!['notFound'], isTrue);
    expect(await KnkApi.sendGroupMessage(base, groupId, from: owner.fipId, fromName: 'Sahip', text: 'x', ts: 6), 'Grup artık mevcut değil.');
  });

  test('unreachable servers fail fast with null / false, never throw', () async {
    const dead = 'http://127.0.0.1:1';
    expect(await KnkApi.getMessages('a__b', receiverServerUrl: dead), isNull);
    expect(await KnkApi.getIncomingRequests(dead, 'fip_x'), isNull);
    expect(await KnkApi.sendMessage(receiverServerUrl: dead, chatKey: 'a__b', from: 'a', text: 't', ts: 1), isFalse);
    expect(await KnkApi.sendGroupMessage(dead, 'g', from: 'a', fromName: 'A', text: 't', ts: 1), isNotNull);
    final (reply, err) = await KnkApi.chatWithPulseAI(dead, [{'role': 'user', 'content': 'selam'}]);
    expect(reply, isNull);
    expect(err, isNotNull);
  });

  test('Pulse AI reports missing configuration cleanly', () async {
    final (reply, err) = await KnkApi.chatWithPulseAI(base, [{'role': 'user', 'content': 'selam'}]);
    expect(reply, isNull);
    expect(err, contains('yapılandırılmadı'));
  });
}
