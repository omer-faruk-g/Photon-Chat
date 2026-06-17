import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// KNK'nın kimlik çekirdeği: FIP (Fake IP) bloğu.
///
/// - 20 satırlık SHA-256 tabanlı hash bloğu üretir (cihaza özgü, rastgele tuz).
/// - Bu bloktan deterministik bir 5 haneli "eşleşme kodu" türetir.
/// - Bloktan benzersiz bir cihaz kimliği (fipId) türetir.
///
/// Bu sınıf yalnızca yerel kimlik üretimi/doğrulama içindir; ağ üzerinden
/// hiçbir şey göndermez.
class FipBlock {
  final List<String> lines; // 20 satır, her biri 64 karakterlik hex (SHA-256)
  final String code; // 5 haneli eşleşme kodu
  final String fipId; // benzersiz cihaz kimliği

  FipBlock({required this.lines, required this.code, required this.fipId});

  /// Yeni, rastgele bir FIP bloğu üretir.
  factory FipBlock.generate() {
    final rnd = Random.secure();
    final lines = <String>[];
    for (var i = 0; i < 20; i++) {
      final saltBytes = List<int>.generate(32, (_) => rnd.nextInt(256));
      final digest = sha256.convert(saltBytes);
      lines.add(digest.toString());
    }
    final code = _deriveCode(lines);
    final fipId = _deriveFipId(lines);
    return FipBlock(lines: lines, code: code, fipId: fipId);
  }

  /// Saklanmış satırlardan bloğu yeniden oluşturur (kod ve id'yi yeniden türetir).
  factory FipBlock.fromLines(List<String> lines) {
    return FipBlock(
      lines: lines,
      code: _deriveCode(lines),
      fipId: _deriveFipId(lines),
    );
  }

  /// 20 satırlık bloktan 5 haneli kod türetir.
  static String _deriveCode(List<String> lines) {
    final joined = lines.join();
    final digest = sha256.convert(utf8.encode(joined));
    final bytes = digest.bytes;
    final value = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    final code = (value.abs() % 100000).toString().padLeft(5, '0');
    return code;
  }

  /// 20 satırlık bloktan benzersiz cihaz kimliği türetir.
  static String _deriveFipId(List<String> lines) {
    final digest = sha256.convert(utf8.encode(lines.first + lines.last));
    return 'fip_${digest.toString().substring(0, 16)}';
  }

  Map<String, dynamic> toJson() => {
        'lines': lines,
        'code': code,
        'fipId': fipId,
      };

  factory FipBlock.fromJson(Map<String, dynamic> json) {
    return FipBlock.fromLines(List<String>.from(json['lines']));
  }
}

/// Sohbet anahtarı: iki fipId'den sıralı, deterministik bir anahtar üretir.
String chatKeyFor(String fipA, String fipB) {
  final ids = [fipA, fipB]..sort();
  return '${ids[0]}__${ids[1]}';
}
