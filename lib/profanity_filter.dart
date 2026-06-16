const _words = [
  'orospu','orsp','orosb','orops','sik','s1k','sikey','sikti','siktir','sikis','sikim','sikici',
  'yarak','yarrak','yar4k','am','amk','amc','amcik','amık','amına','amina','got','göt','g0t',
  'gotveren','götveren','pic','piç','picc','bok','b0k','orospuçocuğu','oç','hassiktir',
  'ibne','ibneler','kahpe','kahpeler','kaltak','sürtük','surtuk','pezevenk','pezeveng','gavat',
  'puşt','pusht','yavs','yavşak','it oğlu','itoğlu','seks','porn','pornn','porno',
  'salak','aptal','gerize','gerzek','moron','ahmak','budala','haysiyetsiz','namussuz',
  'ananı','anani','anasını','anasini','babanı','babani',
  'fuck','fück','fck','fuk','shit','sh1t','bitch','b1tch','bastard','cunt','dick','d1ck','pussy','pu55y','cock','c0ck','nigga','nigger','whore',
];

final _profanityPattern = RegExp(_words.map(RegExp.escape).join('|'), caseSensitive: false, unicode: true);

String filterProfanity(String text) => text.replaceAllMapped(_profanityPattern, (m) => '******');
