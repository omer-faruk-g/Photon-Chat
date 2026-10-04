// Guards outgoing messages: only text + emojis allowed, no URLs or media.

final _urlPattern = RegExp(
  r'https?://|www\.|ftp://|data:image|base64',
  caseSensitive: false,
);

// Görünmez kontrol karakterleri (satır sonu ve sekme hariç).
final _forbiddenChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

const maxMessageLength = 1000;

/// Returns an error message if [text] is not allowed, null if it is fine.
/// Kontrol, temizlenmiş metin üzerinde yapılır; böylece sadece görünmez
/// karakterlerden oluşan bir mesaj boş mesaj olarak gönderilemez.
String? validateMessage(String text) {
  final clean = sanitizeMessage(text);
  if (clean.isEmpty) return 'Boş mesaj gönderilemez.';
  if (clean.length > maxMessageLength) return 'Mesaj en fazla $maxMessageLength karakter olabilir.';
  if (_urlPattern.hasMatch(clean)) return 'Bağlantı veya görsel gönderemezsiniz.';
  return null;
}

/// Strips invisible/control characters before storage.
String sanitizeMessage(String text) =>
    text.replaceAll(_forbiddenChars, '').trim();
