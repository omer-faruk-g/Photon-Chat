import 'package:flutter_test/flutter_test.dart';
import 'package:photon_chat/server_setup_screen.dart';

void main() {
  test('normalizes server urls', () {
    expect(normalizeServerUrl(' https://a.onrender.com/ '), 'https://a.onrender.com');
    expect(normalizeServerUrl('a.onrender.com'), 'https://a.onrender.com');
    expect(normalizeServerUrl('http://localhost:3000//'), 'http://localhost:3000');
  });

  test('rejects invalid urls', () {
    expect(normalizeServerUrl(''), isNull);
    expect(normalizeServerUrl('   '), isNull);
    expect(normalizeServerUrl('ftp://x.com'), isNull);
    expect(normalizeServerUrl('https://'), isNull);
  });
}
