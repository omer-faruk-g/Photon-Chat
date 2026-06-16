/// Mesajların ham depoda düz metin olarak görünmemesi için basit hex
/// obfuskasyonu. Bu gerçek bir kriptografi katmanı DEĞİLDİR; uçtan uca
/// şifreleme için sunucu tarafında TLS + istemci tarafında AES gibi bir
/// algoritma eklenmesi önerilir (bkz. proje notları).
String obfuscate(String text) {
  final bytes = text.codeUnits;
  return bytes.map((b) => b.toRadixString(16).padLeft(4, '0')).join();
}

String deobfuscate(String hex) {
  final buffer = StringBuffer();
  for (var i = 0; i < hex.length; i += 4) {
    final chunk = hex.substring(i, i + 4);
    buffer.writeCharCode(int.parse(chunk, radix: 16));
  }
  return buffer.toString();
}
