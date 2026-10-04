import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photon_chat/e2e.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('both sides derive the same key and can read each other', () async {
    await ensureE2EKeypair();
    final myPub = await getMyPublicKeyBase64();

    // Bora'nın anahtar çifti
    final algo = X25519();
    final bora = await algo.newKeyPair();
    final boraPub = base64.encode((await bora.extractPublicKey()).bytes);

    // Benim tarafım
    final myKey = await deriveSharedKey(boraPub);

    // Bora'nın tarafı: aynı HKDF ile
    final shared = await algo.sharedSecretKey(
      keyPair: bora,
      remotePublicKey: SimplePublicKey(base64.decode(myPub), type: KeyPairType.x25519),
    );
    final boraKey = await Hkdf(hmac: Hmac(Sha256()), outputLength: 32).deriveKey(
      secretKey: SecretKey(await shared.extractBytes()),
      info: utf8.encode('photon-chat-e2e-v1'),
      nonce: const [],
    );

    final cipher = await encryptChatMessage('Merhaba Bora 👋', myKey);
    expect(isE2EMessage(cipher), isTrue);
    expect(cipher.contains('Merhaba'), isFalse);
    expect(await decryptChatMessage(cipher, boraKey), 'Merhaba Bora 👋');

    final back = await encryptChatMessage('Selam!', boraKey);
    expect(await decryptChatMessage(back, myKey), 'Selam!');
  });

  test('plaintext passes through, undecryptable messages return null', () async {
    final key = SecretKey(List<int>.filled(32, 7));
    final other = SecretKey(List<int>.filled(32, 9));
    expect(await decryptChatMessage('düz metin', null), 'düz metin');
    final c = await encryptChatMessage('gizli', key);
    expect(await decryptChatMessage(c, null), isNull);
    expect(await decryptChatMessage(c, other), isNull);
    expect(await decryptChatMessage('${e2ePrefix}bozuk!!', key), isNull);
  });

  test('keypair is stable and wiped on account deletion', () async {
    final a = await getMyPublicKeyBase64();
    expect(await getMyPublicKeyBase64(), a);
    await wipeE2EKeys();
    final b = await getMyPublicKeyBase64();
    expect(b, isNot(a));
  });

  group('group E2E', () {
    Future<SecretKey> wrapKeyFor(SimpleKeyPair kp, String otherPub) async {
      final shared = await X25519().sharedSecretKey(
        keyPair: kp, remotePublicKey: SimplePublicKey(base64.decode(otherPub), type: KeyPairType.x25519));
      return Hkdf(hmac: Hmac(Sha256()), outputLength: 32).deriveKey(
        secretKey: SecretKey(await shared.extractBytes()),
        info: utf8.encode('photon-chat-group-wrap-v1'), nonce: const []);
    }

    test('owner wraps the group key; only the intended member can unwrap it', () async {
      final myPub = await getMyPublicKeyBase64();
      final bora = await X25519().newKeyPair();
      final boraPub = base64.encode((await bora.extractPublicKey()).bytes);
      final (id, key) = generateGroupKeyEntry();
      expect(base64.decode(key), hasLength(32));

      // Ben sahibim: Bora için sararım, Bora kendi tarafında açar
      final wrapped = await wrapGroupKey(groupId: 'g1', keyId: id, keyBase64: key, memberPublicKeyBase64: boraPub);
      expect(wrapped.contains(key), isFalse);
      final opened = jsonDecode(await e2eDecrypt(wrapped, await wrapKeyFor(bora, myPub))) as Map<String, dynamic>;
      expect(opened, {'g': 'g1', 'id': id, 'k': key});

      // Bora sahip: benim için sarar, ben açarım
      final forMe = await e2eEncrypt(jsonEncode({'g': 'g1', 'id': id, 'k': key}), await wrapKeyFor(bora, myPub));
      expect(await unwrapGroupKey(groupId: 'g1', expectedKeyId: id, wrapped: forMe, ownerPublicKeyBase64: boraPub), (id, key));
      // Sunucu başka grubun / başka kimliğin anahtarını sunamaz
      expect(await unwrapGroupKey(groupId: 'g2', expectedKeyId: id, wrapped: forMe, ownerPublicKeyBase64: boraPub), isNull);
      expect(await unwrapGroupKey(groupId: 'g1', expectedKeyId: 'baska', wrapped: forMe, ownerPublicKeyBase64: boraPub), isNull);
      // Sahte sahip anahtarıyla açılamaz
      final evil = base64.encode((await (await X25519().newKeyPair()).extractPublicKey()).bytes);
      expect(await unwrapGroupKey(groupId: 'g1', expectedKeyId: id, wrapped: forMe, ownerPublicKeyBase64: evil), isNull);
      // Birebir sohbet anahtarıyla sarılmış paket kabul edilmez (bağlam ayrımı)
      final dmWrapped = await e2eEncrypt(jsonEncode({'g': 'g1', 'id': id, 'k': key}), await deriveSharedKey(boraPub));
      expect(await unwrapGroupKey(groupId: 'g1', expectedKeyId: id, wrapped: dmWrapped, ownerPublicKeyBase64: boraPub), isNull);
    });

    test('messages round-trip; rotation keeps history readable; missing keys yield null', () async {
      final (id1, k1) = generateGroupKeyEntry();
      final (id2, k2) = generateGroupKeyEntry();
      final m1 = await encryptGroupMessage('eski mesaj', id1, k1);
      final m2 = await encryptGroupMessage('yeni mesaj 🔒', id2, k2);
      expect(isGroupE2EMessage(m1), isTrue);
      expect(groupMessageKeyId(m2), id2);
      expect(m2.contains('yeni'), isFalse);

      final full = {id1: k1, id2: k2};
      expect(await decryptGroupMessage(m1, full), 'eski mesaj');
      expect(await decryptGroupMessage(m2, full), 'yeni mesaj 🔒');
      // Atılan üye yalnızca eski anahtarı bilir: yeni mesajı okuyamaz
      expect(await decryptGroupMessage(m2, {id1: k1}), isNull);
      expect(await decryptGroupMessage('${groupE2EPrefix}bozuk', full), isNull);
      expect(await decryptGroupMessage('düz metin', const {}), 'düz metin');
    });
  });
}
