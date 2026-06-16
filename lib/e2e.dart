import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// E2E Encryption — X25519 + HKDF + AES-GCM
// ---------------------------------------------------------------------------

const _kPrivKeyPref = 'e2e_priv_key_v1';
const _kPubKeyPref = 'e2e_pub_key_v1';

/// Uygulama başlangıcında çağrılır. Anahtar yoksa oluşturur.
Future<void> ensureE2EKeypair() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(_kPrivKeyPref) != null) return;
  final algo = X25519();
  final kp = await algo.newKeyPair();
  final privBytes = await kp.extractPrivateKeyBytes();
  final pubKey = await kp.extractPublicKey();
  prefs.setString(_kPrivKeyPref, base64.encode(privBytes));
  prefs.setString(_kPubKeyPref, base64.encode(pubKey.bytes));
}

/// Kendi public key'imizi Base64 string olarak döndürür.
Future<String> getMyPublicKeyBase64() async {
  final prefs = await SharedPreferences.getInstance();
  final s = prefs.getString(_kPubKeyPref);
  if (s == null) {
    await ensureE2EKeypair();
    return prefs.getString(_kPubKeyPref)!;
  }
  return s;
}

/// İki tarafın shared secret'ından AES-GCM anahtarı türetir.
Future<SecretKey> deriveSharedKey(String theirPublicKeyBase64) async {
  final prefs = await SharedPreferences.getInstance();
  final privBytes = base64.decode(prefs.getString(_kPrivKeyPref)!);
  final theirPubBytes = base64.decode(theirPublicKeyBase64);

  final algo = X25519();
  final myKp = await algo.newKeyPairFromSeed(privBytes);
  final theirPub = SimplePublicKey(theirPubBytes, type: KeyPairType.x25519);
  final shared = await algo.sharedSecretKey(keyPair: myKp, remotePublicKey: theirPub);
  final sharedBytes = await shared.extractBytes();

  // HKDF ile 32-byte AES-GCM anahtarı türet
  final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 32);
  final aesKey = await hkdf.deriveKey(
    secretKey: SecretKey(sharedBytes),
    info: utf8.encode('photon-chat-e2e-v1'),
    nonce: [],
  );
  return aesKey;
}

/// Mesajı AES-GCM ile şifreler. Dönen string Base64 encoded.
Future<String> e2eEncrypt(String plaintext, SecretKey key) async {
  final algo = AesGcm.with256bits();
  final nonce = algo.newNonce();
  final box = await algo.encrypt(
    utf8.encode(plaintext),
    secretKey: key,
    nonce: nonce,
  );
  // nonce(12) + ciphertext + mac(16) hepsini birleştir
  final combined = Uint8List.fromList(nonce + box.cipherText + box.mac.bytes);
  return base64.encode(combined);
}

/// Base64 encoded şifreli mesajı çözer.
Future<String> e2eDecrypt(String cipherBase64, SecretKey key) async {
  final algo = AesGcm.with256bits();
  final bytes = base64.decode(cipherBase64);
  if (bytes.length < 28) throw Exception('E2E: Geçersiz şifreli mesaj');
  final nonce = bytes.sublist(0, 12);
  final mac = Mac(bytes.sublist(bytes.length - 16));
  final cipherText = bytes.sublist(12, bytes.length - 16);
  final box = SecretBox(cipherText, nonce: nonce, mac: mac);
  final plain = await algo.decrypt(box, secretKey: key);
  return utf8.decode(plain);
}

// ---------------------------------------------------------------------------
// Grup şifreleme — rastgele 32-byte grup anahtarı + X25519 sarmalama
// ---------------------------------------------------------------------------

/// Yeni bir grup anahtarı oluşturur.
List<int> generateGroupKey() {
  final rng = Random.secure();
  return List<int>.generate(32, (_) => rng.nextInt(256));
}

/// Grup anahtarını bir üyenin public key'i ile şifreler (X25519+HKDF+AES-GCM).
Future<String> encryptGroupKeyForMember(
    List<int> groupKey, String memberPublicKeyBase64) async {
  final memberKey = await deriveSharedKey(memberPublicKeyBase64);
  final algo = AesGcm.with256bits();
  final nonce = algo.newNonce();
  final box = await algo.encrypt(Uint8List.fromList(groupKey),
      secretKey: memberKey, nonce: nonce);
  final combined =
      Uint8List.fromList(nonce + box.cipherText + box.mac.bytes);
  return base64.encode(combined);
}

/// Kendi shared secret'ımızla sarmalanmış grup anahtarını çözer.
Future<SecretKey> decryptGroupKey(
    String encryptedGroupKeyBase64, String ownerPublicKeyBase64) async {
  final sharedKey = await deriveSharedKey(ownerPublicKeyBase64);
  final algo = AesGcm.with256bits();
  final bytes = base64.decode(encryptedGroupKeyBase64);
  final nonce = bytes.sublist(0, 12);
  final mac = Mac(bytes.sublist(bytes.length - 16));
  final cipherText = bytes.sublist(12, bytes.length - 16);
  final box = SecretBox(cipherText, nonce: nonce, mac: mac);
  final rawKey = await algo.decrypt(box, secretKey: sharedKey);
  return SecretKey(rawKey);
}

/// Grup mesajını grup anahtarıyla şifreler.
Future<String> e2eGroupEncrypt(String plaintext, SecretKey groupKey) async {
  return e2eEncrypt(plaintext, groupKey);
}

/// Grup mesajını grup anahtarıyla çözer.
Future<String> e2eGroupDecrypt(String cipherBase64, SecretKey groupKey) async {
  return e2eDecrypt(cipherBase64, groupKey);
}
