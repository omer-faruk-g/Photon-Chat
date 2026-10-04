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
  await prefs.setString(_kPrivKeyPref, base64.encode(privBytes));
  await prefs.setString(_kPubKeyPref, base64.encode(pubKey.bytes));
}

/// Hesap silinirken anahtar çiftini de yok eder; yeni kimlik yeni anahtar alır.
Future<void> wipeE2EKeys() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kPrivKeyPref);
  await prefs.remove(_kPubKeyPref);
}

/// Kendi public key'imizi Base64 string olarak döndürür.
Future<String> getMyPublicKeyBase64() async {
  final prefs = await SharedPreferences.getInstance();
  final s = prefs.getString(_kPubKeyPref);
  if (s == null || prefs.getString(_kPrivKeyPref) == null) {
    await ensureE2EKeypair();
    return prefs.getString(_kPubKeyPref)!;
  }
  return s;
}

/// İki tarafın shared secret'ından AES-GCM anahtarı türetir.
Future<SecretKey> deriveSharedKey(String theirPublicKeyBase64, {String info = 'photon-chat-e2e-v1'}) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(_kPrivKeyPref) == null) await ensureE2EKeypair();
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
    info: utf8.encode(info),
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
// Sohbet mesajı sarmalama — şifreli mesajlar bir önekle işaretlenir; böylece
// düz metin (eski sürüm) ile çözülemeyen şifreli mesaj birbirinden ayrılır.
// ---------------------------------------------------------------------------

const e2ePrefix = 'e2e1:';

bool isE2EMessage(String text) => text.startsWith(e2ePrefix);

Future<String> encryptChatMessage(String plaintext, SecretKey key) async =>
    '$e2ePrefix${await e2eEncrypt(plaintext, key)}';

/// Düz metni olduğu gibi döndürür; şifreli mesaj çözülemezse null döner.
Future<String?> decryptChatMessage(String text, SecretKey? key) async {
  if (!isE2EMessage(text)) return text;
  if (key == null) return null;
  try {
    return await e2eDecrypt(text.substring(e2ePrefix.length), key);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Grup şifreleme
//
// Grup sahibi rastgele 32 byte'lık bir grup anahtarı üretir ve her üye için
// X25519 + HKDF (ayrı bağlam) + AES-GCM ile "sarar". Sunucu yalnızca sarılmış
// anahtarı taşır. Mesajlar 'e2eg1:<keyId>:<base64>' biçimindedir; bir üye
// atıldığında sahip yeni bir anahtar (yeni keyId) üretip kalan üyelere dağıtır.
// ---------------------------------------------------------------------------

const _groupWrapInfo = 'photon-chat-group-wrap-v1';
const groupE2EPrefix = 'e2eg1:';

/// Grup anahtarı halkası: keyId -> anahtar (Base64). Eski anahtarlar geçmiş mesajlar için saklanır.
typedef GroupKeyring = Map<String, String>;

/// Yeni bir grup anahtarı üretir: (keyId, anahtar Base64).
(String, String) generateGroupKeyEntry() {
  final rng = Random.secure();
  final key = List<int>.generate(32, (_) => rng.nextInt(256));
  final id = List<int>.generate(8, (_) => rng.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return (id, base64.encode(key));
}

/// Grup anahtarını bir üyenin public key'i ile sarar. Paket, grup ve anahtar
/// kimliğini de içerir; açılırken doğrulanır (başka grubun anahtarı sunulamaz).
Future<String> wrapGroupKey({
  required String groupId, required String keyId, required String keyBase64, required String memberPublicKeyBase64,
}) async {
  final wrapKey = await deriveSharedKey(memberPublicKeyBase64, info: _groupWrapInfo);
  return e2eEncrypt(jsonEncode({'g': groupId, 'id': keyId, 'k': keyBase64}), wrapKey);
}

/// Sahibin sardığı grup anahtarını açar: (keyId, anahtar Base64). Geçersizse null.
Future<(String, String)?> unwrapGroupKey({
  required String groupId, required String expectedKeyId, required String wrapped, required String ownerPublicKeyBase64,
}) async {
  try {
    final wrapKey = await deriveSharedKey(ownerPublicKeyBase64, info: _groupWrapInfo);
    final j = jsonDecode(await e2eDecrypt(wrapped, wrapKey)) as Map<String, dynamic>;
    final id = j['id'] as String?;
    final k = j['k'] as String?;
    if (j['g'] != groupId || id == null || id != expectedKeyId || k == null || base64.decode(k).length != 32) return null;
    return (id, k);
  } catch (_) {
    return null;
  }
}

bool isGroupE2EMessage(String text) => text.startsWith(groupE2EPrefix);

Future<String> encryptGroupMessage(String plaintext, String keyId, String keyBase64) async =>
    '$groupE2EPrefix$keyId:${await e2eEncrypt(plaintext, SecretKey(base64.decode(keyBase64)))}';

/// Düz metni olduğu gibi döndürür; şifreli mesajın anahtarı yoksa veya çözülemezse null.
Future<String?> decryptGroupMessage(String text, GroupKeyring keyring) async {
  if (!isGroupE2EMessage(text)) return text;
  final rest = text.substring(groupE2EPrefix.length);
  final sep = rest.indexOf(':');
  if (sep <= 0) return null;
  final key = keyring[rest.substring(0, sep)];
  if (key == null) return null;
  try {
    return await e2eDecrypt(rest.substring(sep + 1), SecretKey(base64.decode(key)));
  } catch (_) {
    return null;
  }
}

/// Şifreli grup mesajının anahtar kimliği (düz metinse null).
String? groupMessageKeyId(String text) {
  if (!isGroupE2EMessage(text)) return null;
  final rest = text.substring(groupE2EPrefix.length);
  final sep = rest.indexOf(':');
  return sep <= 0 ? null : rest.substring(0, sep);
}
