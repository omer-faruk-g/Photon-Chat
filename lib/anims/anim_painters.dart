import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// The five profile intro effects, each drawn from scratch.
///
/// Every painter takes `t` in 0..1 and paints one frame. None of them holds
/// state: particle positions are derived from a seeded pseudo-random so a
/// repaint at the same `t` produces the same frame, rather than reshuffling.

/// Deterministic scatter in 0..1 from an integer seed. Avoids Random(), whose
/// values would change on every repaint and make the particles jitter.
double _noise(int seed) {
  final x = math.sin(seed * 12.9898) * 43758.5453;
  return x - x.floorToDouble();
}

double _easeOut(double t) => 1 - math.pow(1 - t, 3).toDouble();
double _easeIn(double t) => t * t * t;

// ---------------------------------------------------------------------------
// 1. Pixel face — swells with a quickening pulse, then bursts.
// ---------------------------------------------------------------------------

/// A deliberately glitched, asymmetric blocky face.
///
/// Drawn from this bitmap rather than an asset so it stays a few lines of
/// source, and drawn *unlike* any existing game character on purpose — the
/// brief asked for the same swell-and-burst feeling without copying a
/// trademarked design.
const List<String> _facePixels = [
  '..########',
  '.#########',
  '##..###..#',
  '##..##..##',
  '#########.',
  '##.#..##..',
  '#..####..#',
  '##..##..##',
  '.####..###',
  '..######..',
];

class PixelFacePainter extends CustomPainter {
  final double t;
  final Color accent;
  const PixelFacePainter({required this.t, required this.accent});

  /// Fraction of the run spent swelling before the burst.
  static const _burstAt = 0.55;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final cell = math.min(size.width, size.height) / 18;

    if (t < _burstAt) {
      final p = t / _burstAt;
      // Pulses get faster and deeper as the burst approaches, so the rhythm
      // itself signals what is about to happen.
      final beats = 3 + p * 9;
      final pulse = math.sin(p * beats * math.pi).abs() * (0.10 + p * 0.22);
      final scale = 1 + pulse;
      // Flash toward white at each peak.
      final hot = Color.lerp(accent, Colors.white, pulse * 2.2) ?? accent;
      _drawFace(canvas, centre, cell * scale, hot, 1);
      return;
    }

    // Burst: every lit pixel becomes a shard flying outward.
    final p = (t - _burstAt) / (1 - _burstAt);
    final travel = _easeOut(p) * math.max(size.width, size.height) * 0.75;
    final fade = 1 - p;
    var i = 0;
    for (var row = 0; row < _facePixels.length; row++) {
      for (var col = 0; col < _facePixels[row].length; col++) {
        if (_facePixels[row][col] != '#') continue;
        i++;
        final angle = _noise(i) * math.pi * 2;
        final speed = 0.35 + _noise(i + 977) * 0.65;
        final base = _cellCentre(centre, cell, row, col);
        final pos = base +
            Offset(math.cos(angle), math.sin(angle)) * travel * speed;
        final paint = Paint()
          ..color = (Color.lerp(Colors.white, accent, p) ?? accent)
              .withOpacity(fade.clamp(0, 1));
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(angle + p * 4);
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero, width: cell * (1 - p * 0.5), height: cell * (1 - p * 0.5)),
          paint,
        );
        canvas.restore();
      }
    }
  }

  Offset _cellCentre(Offset centre, double cell, int row, int col) {
    final rows = _facePixels.length;
    final cols = _facePixels[0].length;
    return centre +
        Offset((col - cols / 2 + 0.5) * cell, (row - rows / 2 + 0.5) * cell);
  }

  void _drawFace(
      Canvas canvas, Offset centre, double cell, Color colour, double opacity) {
    final paint = Paint()..color = colour.withOpacity(opacity.clamp(0, 1));
    for (var row = 0; row < _facePixels.length; row++) {
      for (var col = 0; col < _facePixels[row].length; col++) {
        if (_facePixels[row][col] != '#') continue;
        final c = _cellCentre(centre, cell, row, col);
        canvas.drawRect(
          Rect.fromCenter(center: c, width: cell * 0.94, height: cell * 0.94),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelFacePainter old) =>
      old.t != t || old.accent != accent;
}

// ---------------------------------------------------------------------------
// 2. Wave — four lines sweep across; the profile is hidden until they pass.
// ---------------------------------------------------------------------------

class WavePainter extends CustomPainter {
  final double t;
  final Color accent;
  final Color veil;
  const WavePainter(
      {required this.t, required this.accent, required this.veil});

  @override
  void paint(Canvas canvas, Size size) {
    // The veil is what actually hides the profile. It retreats downward as the
    // waves travel, so the content is uncovered in the waves' wake.
    final reveal = _easeOut(t);
    final veilTop = size.height * reveal;
    canvas.drawRect(
      Rect.fromLTWH(0, veilTop, size.width, size.height - veilTop + 1),
      Paint()..color = veil,
    );

    for (var line = 0; line < 4; line++) {
      final phase = t * math.pi * 2.4 + line * 0.7;
      final y = veilTop + line * size.height * 0.045;
      if (y > size.height) continue;
      final path = Path();
      final amp = size.height * 0.035 * (1 - line * 0.15);
      for (var x = 0.0; x <= size.width; x += 6) {
        final k = x / size.width;
        final dy = math.sin(k * math.pi * 3 + phase) * amp;
        if (x == 0) {
          path.moveTo(x, y + dy);
        } else {
          path.lineTo(x, y + dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 - line * 0.4
          ..color = accent.withOpacity((0.9 - line * 0.18).clamp(0, 1)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant WavePainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// 3. Balloon — sways until tapped, then bursts.
// ---------------------------------------------------------------------------

class BalloonPainter extends CustomPainter {
  /// Sway phase while waiting, in radians.
  final double sway;

  /// Burst progress, 0 while still waiting.
  final double pop;
  final Color accent;
  const BalloonPainter(
      {required this.sway, required this.pop, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height * 0.36);
    final r = math.min(size.width, size.height) * 0.16;

    if (pop <= 0) {
      final drift = math.sin(sway) * size.width * 0.035;
      final at = centre + Offset(drift, math.sin(sway * 0.7) * r * 0.08);
      _drawString(canvas, at, r, size, sway);
      _drawBalloon(canvas, at, r);
      return;
    }

    // Burst: the skin tears into wedges that fly outward.
    final travel = _easeOut(pop) * math.max(size.width, size.height) * 0.6;
    final fade = (1 - pop).clamp(0.0, 1.0);
    const shards = 14;
    for (var i = 0; i < shards; i++) {
      final angle = (i / shards) * math.pi * 2 + _noise(i) * 0.4;
      final speed = 0.5 + _noise(i + 41) * 0.7;
      final pos = centre + Offset(math.cos(angle), math.sin(angle)) * travel * speed;
      final wedge = Path()
        ..moveTo(0, 0)
        ..lineTo(r * 0.42, -r * 0.16)
        ..lineTo(r * 0.34, r * 0.2)
        ..close();
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle + pop * 5);
      canvas.scale((1 - pop * 0.6).clamp(0.1, 1.0));
      canvas.drawPath(wedge, Paint()..color = accent.withOpacity(fade));
      canvas.restore();
    }
    // Shockwave ring.
    //
    // Drawn as an explicit filled annulus rather than a stroked circle. A
    // stroked circle whose radius grows past the canvas rendered as a filled
    // rectangle-minus-circle on a full-screen canvas — a white wash over the
    // whole profile — while looking correct in the small shop preview. An
    // annulus cannot degenerate that way, and the radius is capped so the ring
    // leaves the screen instead of growing unboundedly.
    if (pop < 0.6) {
      final k = pop / 0.6;
      final maxR = math.max(size.width, size.height);
      final mid = math.min(r + _easeOut(k) * r * 3.2, maxR);
      final band = 3 * (1 - k) + 1;
      final ring = Path.combine(
        ui.PathOperation.difference,
        Path()
          ..addOval(Rect.fromCircle(center: centre, radius: mid + band / 2)),
        Path()
          ..addOval(Rect.fromCircle(
              center: centre, radius: math.max(0, mid - band / 2))),
      );
      canvas.drawPath(
        ring,
        Paint()..color = Colors.white.withOpacity(((1 - k) * 0.7).clamp(0, 1)),
      );
    }
  }

  void _drawBalloon(Canvas canvas, Offset at, double r) {
    final body = Path()
      ..addOval(Rect.fromCenter(center: at, width: r * 1.85, height: r * 2.1));
    // Knot.
    body.addPolygon([
      at + Offset(-r * 0.16, r * 1.02),
      at + Offset(r * 0.16, r * 1.02),
      at + Offset(0, r * 1.26),
    ], true);
    canvas.drawPath(body, Paint()..color = accent);
    // Highlight so it reads as inflated rather than a flat circle.
    canvas.drawOval(
      Rect.fromCenter(
          center: at + Offset(-r * 0.35, -r * 0.45),
          width: r * 0.5,
          height: r * 0.72),
      Paint()..color = Colors.white.withOpacity(0.28),
    );
  }

  void _drawString(
      Canvas canvas, Offset at, double r, Size size, double sway) {
    final path = Path()..moveTo(at.dx, at.dy + r * 1.26);
    final end = size.height * 0.86;
    for (var y = at.dy + r * 1.26; y < end; y += 8) {
      final k = (y - at.dy) / (end - at.dy);
      path.lineTo(at.dx + math.sin(k * 6 + sway) * r * 0.28 * k, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = accent.withOpacity(0.65),
    );
  }

  @override
  bool shouldRepaint(covariant BalloonPainter old) =>
      old.sway != sway || old.pop != pop;
}

// ---------------------------------------------------------------------------
// 4. Shatter — a stone hits the screen and the cracks stay.
// ---------------------------------------------------------------------------

/// Where the stone lands, as a fraction of the screen. Slightly off-centre so
/// the crack web is not symmetrical.
const Offset _impactAt = Offset(0.42, 0.38);

/// Fraction of the run spent on the stone's flight.
const double _impactMoment = 0.32;

class ShatterPainter extends CustomPainter {
  final double t;
  final Color accent;
  const ShatterPainter({required this.t, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final impact =
        Offset(size.width * _impactAt.dx, size.height * _impactAt.dy);

    if (t < _impactMoment) {
      // Stone flies at the viewer: small and high, growing as it approaches.
      final p = t / _impactMoment;
      final from = Offset(size.width * 0.9, -size.height * 0.15);
      final pos = Offset.lerp(from, impact, _easeIn(p))!;
      final r = math.min(size.width, size.height) * (0.02 + 0.075 * p * p);
      _drawStone(canvas, pos, r, p);
      return;
    }

    final p = ((t - _impactMoment) / (1 - _impactMoment)).clamp(0.0, 1.0);
    _paintCracks(canvas, size, impact, _easeOut(p), accent);

    // Impact flash, brief.
    if (p < 0.25) {
      final k = p / 0.25;
      canvas.drawCircle(
        impact,
        math.min(size.width, size.height) * (0.05 + k * 0.5),
        Paint()..color = Colors.white.withOpacity((1 - k) * 0.5),
      );
    }
  }

  void _drawStone(Canvas canvas, Offset at, double r, double p) {
    final path = Path();
    const points = 7;
    for (var i = 0; i < points; i++) {
      final a = (i / points) * math.pi * 2;
      final rr = r * (0.72 + _noise(i * 13) * 0.5);
      final pt = at + Offset(math.cos(a) * rr, math.sin(a) * rr);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(p * 7);
    canvas.translate(-at.dx, -at.dy);
    canvas.drawPath(path, Paint()..color = const Color(0xFF6E7B7A));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF39413F),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ShatterPainter old) => old.t != t;
}

/// The crack web on its own, fully grown. Painted over the profile for as long
/// as it stays open — the brief was explicit that the screen never heals.
class CrackPainter extends CustomPainter {
  final Color accent;
  const CrackPainter({required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final impact =
        Offset(size.width * _impactAt.dx, size.height * _impactAt.dy);
    _paintCracks(canvas, size, impact, 1, accent);
  }

  @override
  bool shouldRepaint(covariant CrackPainter old) => false;
}

/// Shared crack web so the growing and the settled versions cannot drift apart.
void _paintCracks(
    Canvas canvas, Size size, Offset impact, double grow, Color accent) {
  final reach = math.max(size.width, size.height) * 1.1 * grow;
  const spokes = 11;
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  // Radial fractures, each kinked a couple of times so they do not read as
  // clean rays.
  final ends = <Offset>[];
  for (var i = 0; i < spokes; i++) {
    final angle = (i / spokes) * math.pi * 2 + _noise(i * 7) * 0.5;
    final len = reach * (0.45 + _noise(i * 31) * 0.55);
    var cur = impact;
    var dir = angle;
    final path = Path()..moveTo(cur.dx, cur.dy);
    const segs = 3;
    for (var s = 0; s < segs; s++) {
      dir += (_noise(i * 100 + s) - 0.5) * 0.6;
      final step = len / segs;
      cur = cur + Offset(math.cos(dir), math.sin(dir)) * step;
      path.lineTo(cur.dx, cur.dy);
    }
    ends.add(cur);
    canvas.drawPath(
        path,
        stroke
          ..strokeWidth = 2.2
          ..color = Colors.white.withOpacity(0.55 * grow));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 0.9
          ..color = accent.withOpacity(0.35 * grow));
  }

  // Concentric webbing tying the fractures together.
  for (final ring in [0.35, 0.62, 0.88]) {
    final path = Path();
    for (var i = 0; i <= spokes; i++) {
      final idx = i % spokes;
      final pt = Offset.lerp(impact, ends[idx], ring * grow)!;
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = Colors.white.withOpacity(0.3 * grow));
  }

  // Pulverised centre.
  canvas.drawCircle(
      impact,
      math.min(size.width, size.height) * 0.022,
      Paint()..color = Colors.white.withOpacity(0.6 * grow));
}

// ---------------------------------------------------------------------------
// 5. Spiral — trailing arms behind the content as it spins into place.
// ---------------------------------------------------------------------------

class SpiralPainter extends CustomPainter {
  final double t;
  final Color accent;
  const SpiralPainter({required this.t, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final maxR = math.max(size.width, size.height) * 0.75;
    // Arms wind in as the content settles, and fade out at the end so the
    // profile is not left sitting under a pattern.
    final fade = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);
    final spin = t * math.pi * 3;

    for (var arm = 0; arm < 3; arm++) {
      final path = Path();
      final armOffset = (arm / 3) * math.pi * 2;
      var started = false;
      for (var s = 0.0; s <= 1.0; s += 0.012) {
        final a = armOffset + spin + s * math.pi * 4;
        final r = maxR * s * (1 - t * 0.55);
        final pt = centre + Offset(math.cos(a) * r, math.sin(a) * r);
        if (!started) {
          path.moveTo(pt.dx, pt.dy);
          started = true;
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4 - arm * 0.5
          ..color = accent.withOpacity((0.75 - arm * 0.2) * fade),
      );
    }
  }

  @override
  bool shouldRepaint(covariant SpiralPainter old) => old.t != t;
}
