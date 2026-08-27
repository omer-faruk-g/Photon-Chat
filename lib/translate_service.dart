import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TranslateService {
  static final Map<String, String> _cache = {};
  static const int _maxCacheEntries = 512;

  static void _cachePut(String key, String value) {
    if (_cache.length >= _maxCacheEntries) {
      // Drop the oldest entry (Dart maps preserve insertion order).
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  /// Translate text using Google Translate free endpoint.
  /// Target language comes from SharedPreferences 'knk_lang_v1' (default 'tr').
  static Future<String> translate(String text, {String? targetLang}) async {
    final prefs = await SharedPreferences.getInstance();
    final target = targetLang ?? prefs.getString('knk_lang_v1') ?? 'tr';

    // Full text in cache key — hashCode collides for distinct strings.
    final cacheKey = '$target $text';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    try {
      final url = Uri.parse(
        'https://translate.googleapis.com/translate_a/single'
        '?client=gtx&sl=auto&tl=$target&dt=t&q=${Uri.encodeComponent(text)}',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translated =
            (data[0] as List).map((e) => e[0] as String).join('');
        _cachePut(cacheKey, translated);
        return translated;
      }
      return text;
    } catch (_) {
      return text;
    }
  }

  /// Strict variant used for UI string translation. Throws on any failure so
  /// callers can roll back the language switch instead of silently caching the
  /// source-language text.
  ///
  /// [sourceLang] defaults to Turkish because every UI string starts life in
  /// `_baseTr`. Auto-detection guesses wrong on short isolated tokens — "Dil",
  /// "Erkek" and "KODUM" all came back unchanged — which shipped untranslated
  /// labels into otherwise fully translated screens.
  static Future<String> translateStrict(String text, {required String targetLang, String sourceLang = 'tr'}) async {
    final cacheKey = '$sourceLang>$targetLang $text';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;
    final url = Uri.parse(
      'https://translate.googleapis.com/translate_a/single'
      '?client=gtx&sl=$sourceLang&tl=$targetLang&dt=t&q=${Uri.encodeComponent(text)}',
    );
    final response = await http.get(url).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Translate HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    final translated = (data[0] as List).map((e) => e[0] as String).join('');
    if (translated.trim().isEmpty) throw StateError('empty translation');
    _cachePut(cacheKey, translated);
    return translated;
  }
}
