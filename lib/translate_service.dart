import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TranslateService {
  static final Map<String, String> _cache = {};

  /// Translate text using Google Translate free endpoint.
  /// Target language comes from SharedPreferences 'knk_lang_v1' (default 'tr').
  static Future<String> translate(String text, {String? targetLang}) async {
    final prefs = await SharedPreferences.getInstance();
    final target = targetLang ?? prefs.getString('knk_lang_v1') ?? 'tr';

    final cacheKey = '${text.hashCode}_$target';
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
        _cache[cacheKey] = translated;
        return translated;
      }
      return text;
    } catch (_) {
      return text;
    }
  }
}
