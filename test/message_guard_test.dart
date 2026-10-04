import 'package:flutter_test/flutter_test.dart';
import 'package:photon_chat/message_guard.dart';
import 'package:photon_chat/theme.dart';

void main() {
  test('rejects empty and whitespace-only messages', () {
    expect(validateMessage(''), isNotNull);
    expect(validateMessage('   \n '), isNotNull);
  });

  test('rejects messages made only of invisible control characters', () {
    expect(validateMessage('\x01\x02\x7F'), isNotNull);
  });

  test('rejects links and inline images', () {
    expect(validateMessage('bak https://x.com'), isNotNull);
    expect(validateMessage('www.ornek.com'), isNotNull);
    expect(validateMessage('data:image/png;base64,AAA'), isNotNull);
  });

  test('enforces max length', () {
    expect(validateMessage('a' * maxMessageLength), isNull);
    expect(validateMessage('a' * (maxMessageLength + 1)), isNotNull);
  });

  test('accepts normal text and emoji', () {
    expect(validateMessage('Merhaba 👋 nasılsın?'), isNull);
  });

  test('sanitize strips control chars but keeps newlines', () {
    expect(sanitizeMessage(' a\x00b\nc '), 'ab\nc');
  });

  test('Turkish-aware uppercase for section labels', () {
    expect(trUpper('Kişiler · 3'), 'KİŞİLER · 3');
    expect(trUpper('Davetler'), 'DAVETLER');
    expect(trUpper('Kapalı ışık'), 'KAPALI IŞIK');
  });
}
