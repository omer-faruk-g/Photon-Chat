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

  test('group key wrapping produces ciphertext', () async {
    final algo = X25519();
    final member = await algo.newKeyPair();
    final memberPub = base64.encode((await member.extractPublicKey()).bytes);
    final groupKey = generateGroupKey();
    final wrapped = await encryptGroupKeyForMember(groupKey, memberPub);
    expect(wrapped, isNotEmpty);
  });
}
