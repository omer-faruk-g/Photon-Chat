// Displays only — filters profanity at render time, stored data is never modified.
import 'package:shared_preferences/shared_preferences.dart';
import 'translate_service.dart';

// Language-specific profanity lists. When user picks a UI language,
// only that language's list applies to the CURRENT session — so an
// English speaker typing "I am" doesn't get "am" (Turkish) censored.
// Turkish is always included when active because content is predominantly TR.
const Map<String, List<String>> _wordsByLang = {
  'tr': [
    'orospu', 'orsp', 'orosb', 'orops',
    'sik', 's1k', 'sikey', 'sikti', 'siktir', 'sikis', 'sikim', 'sikici',
    'yarak', 'yarrak', 'yar4k',
    // NOTE: 'am' removed because too many false positives (English "I am",
    // Turkish "amaç", "amelî" etc.). We keep the derivatives.
    'amk', 'amcik', 'amık', 'amına', 'amina',
    'got', 'göt', 'g0t', 'gotveren', 'götveren',
    'pic', 'piç', 'picc',
    'bok', 'b0k',
    'orospuçocuğu', 'oç',
    'hassiktir', 'hassedeyim', 'ibne', 'ibneler',
    'kahpe', 'kahpeler',
    'kaltak',
    'sürtük', 'surtuk',
    'pezevenk', 'pezeveng',
    'gavat',
    'puşt', 'pusht',
    'yavşak',
    'itoğlu',
    'salak', 'aptal', 'gerize', 'gerzek', 'moron', 'ahmak', 'budala',
    'haysiyetsiz', 'namussuz',
    'gavur', 'kızılbaş', 'kızılbas', 'zenci', 'z3nci',
    'ananı', 'anani', 'anasını', 'anasini', 'babanı', 'babani',
  ],
  'en': [
    'fuck', 'fück', 'fck', 'fuk',
    'shit', 'sh1t',
    'bitch', 'b1tch',
    'bastard',
    'cunt',
    'dick', 'd1ck',
    'pussy', 'pu55y',
    'cock', 'c0ck',
    'nigga', 'nigger',
    'whore',
    'asshole', 'motherfucker', 'faggot',
  ],
  'de': ['scheisse', 'scheiße', 'arschloch', 'fotze', 'schwanz', 'hurensohn'],
  'fr': ['merde', 'putain', 'connard', 'salope', 'enculé', 'pute'],
  'es': ['mierda', 'joder', 'puta', 'coño', 'cabrón', 'gilipollas'],
  'it': ['cazzo', 'merda', 'stronzo', 'puttana', 'vaffanculo', 'figa'],
  'pt': ['merda', 'porra', 'caralho', 'puta', 'foda', 'cu'],
  'ru': ['блядь', 'сука', 'хуй', 'пизда', 'ебать'],
  'ar': ['كس', 'زب', 'شرموطة', 'قحبة'],
};

String _cachedLang = 'tr';
RegExp _cachedPattern = _build('tr');

RegExp _build(String lang) {
  // Combine Turkish + user's UI language (Turkish is the app's base content lang).
  final wordSet = <String>{...?_wordsByLang['tr']};
  if (lang != 'tr') wordSet.addAll(_wordsByLang[lang] ?? const []);
  if (wordSet.isEmpty) return RegExp(r'a^'); // matches nothing
  return RegExp(
    '(?<![\\p{L}\\p{N}])(?:${wordSet.map(RegExp.escape).join('|')})(?![\\p{L}\\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
}

Future<void> reloadProfanityForCurrentLang() async {
  final prefs = await SharedPreferences.getInstance();
  final lang = prefs.getString('knk_lang_v1') ?? 'tr';
  if (lang != _cachedLang) {
    _cachedLang = lang;
    _cachedPattern = _build(lang);
  }
}

String filterProfanity(String text) =>
    text.replaceAllMapped(_cachedPattern, (m) => '******');

/// Translates [text] to Turkish first, then censors any matched profanity
/// spans in the ORIGINAL text by position mapping (approximate: censors whole
/// original if translated version contains profanity).
Future<String> filterProfanityAsync(String text) async {
  await reloadProfanityForCurrentLang();
  if (filterProfanity(text) != text) return filterProfanity(text);
  try {
    final tr = await TranslateService.translate(text, targetLang: 'tr');
    if (_cachedPattern.hasMatch(tr)) {
      return text.replaceAll(RegExp(r'\S+'), '******');
    }
  } catch (_) {}
  return text;
}
