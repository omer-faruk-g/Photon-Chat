// Displays only — filters profanity before rendering, does not alter stored messages.
final _profanityPattern = RegExp(
  r'orospu|orsp|sik|s[iı]k|piç|pic|göt|got|amk|bok|bok|meme|yarrak|yarak|yavşak|yavşak|oç|puşt|ibne|kahpe|kaltak|sürtük|surtuk|pezevenk|gavat|it[\s]oğlu|salak|mal[\s]|aptal|gerize|gerzek|haysiyetsiz|bok\w*|lanet\w*|s[iı]ktir|hassiktir|amına|anasını|ananı|ananın|boku|götü|sikeyim|sikerim|sikiş|sikişme|götveren|orospu\s*çoc|oç\w*',
  caseSensitive: false,
);

String filterProfanity(String text) {
  return text.replaceAllMapped(_profanityPattern, (m) => '******');
}
