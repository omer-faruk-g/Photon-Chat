// Displays only — filters profanity at render time, stored data is never modified.

const _words = [
  'orospu', 'orsp', 'orosb', 'orops',
  'sik', 's1k', 'sikey', 'sikti', 'siktir', 'sikis', 'sikim', 'sikici',
  'yarak', 'yarrak', 'yar4k',
  'am', 'amk', 'amc', 'amcik', 'amık', 'amına', 'amina',
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
  'yavs', 'yavs ak', 'yavşak',
  'it oğlu', 'itoğlu',
  'seks', 'porn', 'pornn', 'porno',
  'göğüs', 'meme', 'kalca', 'kalça',
  'salak', 'aptal', 'gerize', 'gerzek', 'mal', 'moron', 'ahmak', 'budala',
  'haysiyetsiz', 'namussuz', 'adi',
  'gavur', 'kızılbaş', 'kızılbas', 'zenci', 'z3nci',
  'ananı', 'anani', 'anasını', 'anasini', 'babanı', 'babani',
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
