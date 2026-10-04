import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'profanity_filter.dart';

/// Merkezi içerik tarayıcısı — metin (küfür) + görsel (deri rengi analizi).
/// Her iki kontrol de geçilmeden içerik gönderilmez / kaydedilmez.
class NsfwScanner {
  // Tarama eşiği: piksellerin %35'inden fazlası deri tonu ise uygunsuz say
  static const _skinThreshold = 0.35;

  /// Metinde küfür/uygunsuz kelime var mı?
  static bool hasTextViolation(String text) {
    if (text.trim().isEmpty) return false;
    return filterProfanity(text) != text;
  }

  /// Görsel verisinde aşırı deri tonu var mı? (uygunsuz içerik heuristiği)
  /// Performans için 120x120'ye küçültülür.
  static Future<bool> hasImageViolation(Uint8List bytes) async {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return false;
      final small = img.copyResize(image, width: 120, height: 120);
      int skinPixels = 0;
      final total = small.width * small.height;
      for (int y = 0; y < small.height; y++) {
        for (int x = 0; x < small.width; x++) {
          final p = small.getPixel(x, y);
          if (_isSkinTone(p.r.toInt(), p.g.toInt(), p.b.toInt())) {
            skinPixels++;
          }
        }
      }
      return (skinPixels / total) > _skinThreshold;
    } catch (_) {
      return false;
    }
  }

  /// Birden fazla kare için toplu görsel tarama (GIF kareleri için)
  static Future<bool> hasAnyFrameViolation(List<Uint8List> frames) async {
    for (final frame in frames) {
      if (await hasImageViolation(frame)) return true;
    }
    return false;
  }

  /// Skin tone heuristiği — RGB Kovac algoritması (basit versiyon)
  static bool _isSkinTone(int r, int g, int b) {
    return r > 95 &&
        g > 40 &&
        b > 20 &&
        r > g &&
        r > b &&
        (r - g).abs() > 15 &&
        r - b > 15;
  }
}
