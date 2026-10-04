// Displays only — filters profanity at render time, stored data is never modified.
//
// Eşleştirme kelime bazlıdır: "tamam", "zaman", "class", "malzeme" gibi masum
// kelimelerin içindeki harf dizileri sansürlenmez.

/// Yalnızca kelimenin tamamı eşleşirse sansürlenir (kısa / çok anlamlı kökler).
const _exactWords = {
  'am', 'amk', 'amq', 'aq', 'amc', 'amcık', 'amcik', 'amına', 'amina', 'amını', 'amini',
  'sik', 'sikik', 'sikim', 'sikis', 'sikiş', 'sikey', 'sikti', 'sikici',
  'yarak', 'yarrak',
  'göt', 'pic', 'piç', 'picc', 'bok', 'oç',
  'orsp', 'orosb', 'orops',
  'seks', 'porn', 'pornn', 'porno',
  'salak', 'aptal', 'gerize', 'gerzek', 'moron', 'ahmak', 'budala',
  'haysiyetsiz', 'namussuz',
  'gavur', 'kızılbaş', 'kızılbas', 'zenci',
  'itoğlu', 'itoglu',
  'fck', 'fuk', 'ass', 'dick', 'cock',
};

/// Kelime bu köklerle başlıyorsa sansürlenir (Türkçe ekler dahil: "siktirgit", "orospunun").
const _prefixWords = [
  'orospu', 'orosbu', 'orspu',
  'siktir', 'sikerim', 'sikeyim', 'sikiyim', 'sikicem', 'sikeceğim', 'siktiğim',
  'amcığ', 'amcik', 'amına', 'yarrağ', 'yarağ',
  'götveren', 'gotveren', 'götoş',
  'hassiktir', 'hassedeyim',
  'ibne', 'kahpe', 'kaltak', 'sürtük', 'surtuk',
  'pezevenk', 'pezeveng', 'gavat', 'puşt', 'pusht', 'yavşak', 'yavsak',
  'gerizekalı', 'gerizekali',
  'orospuçocuğu', 'orospucocugu',
  'fuck', 'fück', 'motherfuck', 'shit', 'bitch', 'bastard', 'cunt', 'pussy',
  'nigga', 'nigger', 'whore',
];

final _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);
final _phrasePattern = RegExp(r'\bit\s+oğlu\b', caseSensitive: false, unicode: true);

const _leet = {'0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a'};

/// Türkçe kurallara göre küçük harfe çevirir (I → ı, İ → i).
String _lowerTr(String s) => s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

bool _isBad(String norm) {
  if (_exactWords.contains(norm)) return true;
  for (final p in _prefixWords) {
    if (norm.startsWith(p)) return true;
  }
  return false;
}

bool _isProfane(String word) {
  final lower = _lowerTr(word);
  if (_isBad(lower)) return true;
  // Büyük harfle yazılmış İngilizce kelimeler (SHIT) için ASCII küçültme de dene.
  final asciiLower = word.toLowerCase();
  if (asciiLower != lower && _isBad(asciiLower)) return true;
  // Leetspeak (s1k, sh1t, a55)
  if (lower.contains(RegExp(r'[0-9]'))) {
    final deLeet = lower.split('').map((c) => _leet[c] ?? c).join();
    if (deLeet != lower && _isBad(deLeet)) return true;
  }
  return false;
}

String filterProfanity(String text) {
  if (text.isEmpty) return text;
  final filtered = text.replaceAllMapped(_wordPattern, (m) {
    final w = m[0]!;
    return _isProfane(w) ? '*' * w.length : w;
  });
  return filtered.replaceAllMapped(_phrasePattern, (m) => '*' * m[0]!.length);
}
