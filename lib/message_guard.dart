// Guards outgoing messages: only text + emojis allowed, no URLs or media.
import 'i18n.dart';

final _urlPattern = RegExp(
  r'https?://|www\.|ftp://|data:image|base64',
  caseSensitive: false,
);

// Strips every character that is not a letter, digit, whitespace,
// common punctuation, or a Unicode symbol/emoji (code point  +).
final _forbiddenChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

const _maxLength = 1000;

/// Returns an error message if [text] is not allowed, null if it is fine.
String? validateMessage(String text) {
  if (text.trim().isEmpty) return AppLang.instance.t('msgEmpty');
  if (text.length > _maxLength) {
    return AppLang.instance.t('msgTooLong').replaceAll('{n}', '$_maxLength');
  }
  if (_urlPattern.hasMatch(text)) return AppLang.instance.t('msgNoLinks');
  return null;
}

/// Strips invisible/control characters before storage.
String sanitizeMessage(String text) =>
    text.replaceAll(_forbiddenChars, '').trim();
