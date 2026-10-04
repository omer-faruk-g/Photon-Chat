import 'package:flutter_test/flutter_test.dart';
import 'package:photon_chat/fip.dart';

void main() {
  test('generates 20 sha256 lines, a 5 digit code and a stable fipId', () {
    final f = FipBlock.generate();
    expect(f.lines, hasLength(20));
    expect(f.lines.every((l) => RegExp(r'^[0-9a-f]{64}$').hasMatch(l)), isTrue);
    expect(f.code, matches(RegExp(r'^\d{5}$')));
    expect(f.fipId, matches(RegExp(r'^fip_[0-9a-f]{16}$')));
  });

  test('round-trips through JSON with the same code and id', () {
    final f = FipBlock.generate();
    final g = FipBlock.fromJson(f.toJson());
    expect(g.code, f.code);
    expect(g.fipId, f.fipId);
    expect(g.lines, f.lines);
  });

  test('chatKeyFor is symmetric', () {
    expect(chatKeyFor('fip_a', 'fip_b'), chatKeyFor('fip_b', 'fip_a'));
    expect(chatKeyFor('fip_a', 'fip_b'), 'fip_a__fip_b');
  });
}
