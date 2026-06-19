// Displays only — filters profanity at render time, stored data is never modified.
import 'translate_service.dart';

const _words = [
  // Temel kökler
  'orospu', 'orsp', 'orosb', 'orops',
  'sik', 's1k', 'sikey', 'sikti', 'siktir', 'sikis', 'sikim', 'sikici',
  'yarak', 'yarrak', 'yar4k',
  'am', 'amk', 'amc', 'amcik', 'amık', 'amına', 'amina',
  'got', 'göt', 'g0t', 'gotveren', 'götveren',
  'pic', 'piç', 'picc',
  'bok', 'b0k',
  'orospuçocuğu', 'oç',
  // Türevler ve bileşik formlar
  'hassiktir', 'hassedeyim', 'ibne', 'ibneler',
  'kahpe', 'kahpeler',
  'kaltak',
  'sürtük', 'surtuk',
  'pezevenk', 'pezeveng',
  'gavat',
  'puşt', 'pusht',
  'yavs', 'yavs ak', 'yavşak',
  'it oğlu', 'itoğlu',
  // Cinsel içerikli
  'seks', 'porn', 'pornn', 'porno',
  'göğüs', 'meme', 'kalca', 'kalça',
  // Hakaret
  'salak', 'aptal', 'gerize', 'gerzek', 'mal', 'moron', 'ahmak', 'budala',
  'haysiyetsiz', 'namussuz', 'adi',
  // Dini / etnik hakaret (çift yönlü filtre)
  'gavur', 'kızılbaş', 'kızılbas', 'zenci', 'z3nci',
  // Anası / babanı içeren formlar
  'ananı', 'anani', 'anasını', 'anasini', 'babanı', 'babani',
  // İngilizce kökenli (sık kullanılan)
  'fuck', 'fück', 'fck', 'fuk',
  'shit', 'sh1t',
  'bitch', 'b1tch',
  'ass', 'a55',
  'bastard',
  'cunt',
  'dick', 'd1ck',
  'pussy', 'pu55y',
  'cock', 'c0ck',
  'nigga', 'nigger',
  'whore',
];

final _profanityPattern = RegExp(
  _words.map(RegExp.escape).join('|'),
  caseSensitive: false,
  unicode: true,
);

String filterProfanity(String text) =>
    text.replaceAllMapped(_profanityPattern, (m) => '******');

/// Translates [text] to Turkish first, then censors any matched profanity
/// spans in the ORIGINAL text by position mapping (approximate: censors whole
/// original if translated version contains profanity).
Future<String> filterProfanityAsync(String text) async {
  if (filterProfanity(text) != text) return filterProfanity(text);
  try {
    final tr = await TranslateService.translate(text, targetLang: 'tr');
    if (_profanityPattern.hasMatch(tr)) {
      return text.replaceAll(RegExp(r'\S+'), '******');
    }
  } catch (_) {}
  return text;
}
