// Guards outgoing messages: only text + emojis allowed, no URLs or media.

final _urlPattern = RegExp(
  r'https?://|www\.|ftp://|data:image|base64',
  caseSensitive: false,
);

final _forbiddenChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

const _maxLength = 1000;

String? validateMessage(String text) {
  if (text.trim().isEmpty) return 'Boş mesaj gönderilemez.';
  if (text.length > _maxLength) return 'Mesaj en fazla $_maxLength karakter olabilir.';
  if (_urlPattern.hasMatch(text)) return 'Bağlantı veya görsel gönderemezsiniz.';
  return null;
}

String sanitizeMessage(String text) =>
    text.replaceAll(_forbiddenChars, '').trim();
