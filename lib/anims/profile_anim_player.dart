import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../i18n.dart';
import '../profile_anim.dart';
import '../theme.dart';
import 'anim_painters.dart';

/// Plays a profile's intro animation over the profile content.
///
/// The content is passed as [child] rather than sitting beside this widget so
/// the animations can move it — the spiral flies it in, the balloon burst
/// scatters and settles it. Effects that only reveal it simply fade it up.
///
/// Every effect can be skipped by tapping, so someone opening the same profile
/// ten times a day is never held up. The balloon is the exception: it is
/// *waiting* for that tap, so the tap pops it and the burst plays in full.
class ProfileAnimPlayer extends StatefulWidget {
  final ProfileAnim anim;
  final Color accent;
  final VoidCallback onDone;
  final Widget child;

  /// Off for the shop/settings previews, where the hint would be noise.
  final bool showHint;

  const ProfileAnimPlayer({
    super.key,
    required this.anim,
    required this.accent,
    required this.onDone,
    required this.child,
    this.showHint = true,
  });

  @override
  State<ProfileAnimPlayer> createState() => _ProfileAnimPlayerState();
}

class _ProfileAnimPlayerState extends State<ProfileAnimPlayer>
    with TickerProviderStateMixin {
  /// Drives the effect itself. For the balloon this is the sway-and-wait loop.
  late final AnimationController _c;

  /// Balloon only: the burst, started by a tap or by the wait running out.
  AnimationController? _pop;

  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.anim.duration);

    if (widget.anim.waitsForTap) {
      _pop = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 900))
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _finish();
        });
      // The sway loops while we wait; the controller doubles as the patience
      // timer, so an untouched balloon eventually pops by itself.
      _c
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _burst();
        })
        ..forward();
    } else {
      _c
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _finish();
        })
        ..forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _pop?.dispose();
    super.dispose();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onDone();
  }

  void _burst() {
    if (_finished || (_pop?.isAnimating ?? false) || _pop == null) return;
    if (_pop!.value > 0) return;
    _c.stop();
    _pop!.forward();
  }

  void _onTap() {
    if (_finished) return;
    if (widget.anim.waitsForTap) {
      _burst();
      return;
    }
    // Skip: jump to the end rather than cutting mid-frame, so whatever the
    // effect reveals is in its finished state.
    _c.stop();
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final listenTo = _pop == null
        ? Listenable.merge([_c])
        : Listenable.merge([_c, _pop!]);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: AnimatedBuilder(
        animation: listenTo,
        builder: (context, _) {
          final t = _c.value;
          // The balloon says "tap to pop" from the start, since it is waiting.
          // The others only offer the hint once they are underway, so it does
          // not flash up on effects that are over almost immediately.
          final showHint = widget.showHint &&
              (widget.anim.waitsForTap
                  ? (_pop?.value ?? 0) == 0
                  : t > 0.15 && t < 0.85);
          return Stack(
            fit: StackFit.expand,
            children: [
              _transformedChild(t),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _painterFor(t)),
                ),
              ),
              if (showHint)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: IgnorePointer(
                    child: Text(
                      AppLang.instance.t(widget.anim.waitsForTap
                          ? 'animTapToPop'
                          : 'animTapToSkip'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: PhotonColors.textDim.withOpacity(0.8),
                          fontSize: 11),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// How far along the reveal of the profile content is, 0..1.
  double _revealProgress(double t) => switch (widget.anim) {
        // Hidden until the face bursts, then fades up through the shards.
        ProfileAnim.pixelFace =>
          t < 0.55 ? 0.0 : ((t - 0.55) / 0.45).clamp(0.0, 1.0),
        // Uncovered in the waves' wake.
        ProfileAnim.wave => (t / 0.85).clamp(0.0, 1.0),
        // Nothing until the balloon actually bursts.
        ProfileAnim.balloon => (_pop?.value ?? 0).clamp(0.0, 1.0),
        // Readable straight after the stone lands.
        ProfileAnim.shatter =>
          t < 0.32 ? 0.0 : ((t - 0.32) / 0.4).clamp(0.0, 1.0),
        ProfileAnim.spiral => t.clamp(0.0, 1.0),
        ProfileAnim.none => 1.0,
      };

  Widget _transformedChild(double t) {
    final p = _revealProgress(t);
    if (p <= 0) return const SizedBox.shrink();

    switch (widget.anim) {
      case ProfileAnim.spiral:
        // Flies in along a shrinking spiral and unwinds into place.
        final e = 1 - math.pow(1 - p, 3).toDouble();
        final angle = (1 - e) * math.pi * 2.5;
        final radius = (1 - e) * 160;
        return Opacity(
          opacity: (p * 1.6).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(math.cos(angle) * radius, math.sin(angle) * radius),
            child: Transform.rotate(
              angle: angle,
              child: Transform.scale(scale: 0.4 + e * 0.6, child: widget.child),
            ),
          ),
        );

      case ProfileAnim.balloon:
        // Thrown outward by the burst, then settling back into place.
        final e = 1 - math.pow(1 - p, 3).toDouble();
        return Opacity(
          opacity: (p * 1.8).clamp(0.0, 1.0),
          child: Transform.scale(scale: 1.45 - e * 0.45, child: widget.child),
        );

      case ProfileAnim.pixelFace:
        return Opacity(
          opacity: p,
          child: Transform.scale(scale: 0.94 + p * 0.06, child: widget.child),
        );

      default:
        return Opacity(opacity: p, child: widget.child);
    }
  }

  CustomPainter? _painterFor(double t) => switch (widget.anim) {
        ProfileAnim.pixelFace =>
          PixelFacePainter(t: t, accent: widget.accent),
        ProfileAnim.wave => WavePainter(
            t: t, accent: widget.accent, veil: PhotonColors.bg),
        ProfileAnim.balloon => BalloonPainter(
            sway: t * math.pi * 6,
            pop: _pop?.value ?? 0,
            accent: widget.accent,
          ),
        ProfileAnim.shatter => ShatterPainter(t: t, accent: widget.accent),
        ProfileAnim.spiral => SpiralPainter(t: t, accent: widget.accent),
        ProfileAnim.none => null,
      };
}

/// The crack web left behind by the shatter effect, drawn over the profile for
/// as long as it stays open.
class CrackResidue extends StatelessWidget {
  final Color accent;
  const CrackResidue({super.key, required this.accent});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: CrackPainter(accent: accent));
}

/// Small looping preview used by the shop and the picker, so someone can see
/// what they are buying without opening a profile.
class ProfileAnimPreview extends StatefulWidget {
  final ProfileAnim anim;
  final Color accent;
  final double height;
  const ProfileAnimPreview({
    super.key,
    required this.anim,
    required this.accent,
    this.height = 170,
  });

  @override
  State<ProfileAnimPreview> createState() => _ProfileAnimPreviewState();
}

class _ProfileAnimPreviewState extends State<ProfileAnimPreview> {
  /// Bumped to restart the player each time a run finishes, so the preview
  /// loops instead of stopping on the first pass.
  int _run = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.anim == ProfileAnim.none) {
      return SizedBox(height: widget.height);
    }
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: PhotonColors.bg,
          child: ProfileAnimPlayer(
            key: ValueKey('${widget.anim.id}_$_run'),
            anim: widget.anim,
            accent: widget.accent,
            showHint: false,
            onDone: () {
              if (mounted) setState(() => _run++);
            },
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}
