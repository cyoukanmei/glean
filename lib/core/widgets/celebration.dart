import 'dart:math';

import 'package:flutter/material.dart';

/// One-shot "finished!" celebration: a confetti burst plus a badge that pops
/// in, holds, then fades. Self-drawn (no Lottie asset to license or load).
///
/// Never intercepts touches, so the page below stays usable while it plays.
class CelebrationBurst extends StatefulWidget {
  const CelebrationBurst({
    super.key,
    required this.label,
    this.onDone,
    this.seed = 7,
  });

  final String label;
  final VoidCallback? onDone;

  /// Fixed per burst so tests and screenshots are reproducible.
  final int seed;

  static const duration = Duration(milliseconds: 1600);

  @override
  State<CelebrationBurst> createState() => _CelebrationBurstState();
}

class _CelebrationBurstState extends State<CelebrationBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: CelebrationBurst.duration,
  );
  late final List<_Particle> _particles = _Particle.burst(widget.seed);

  // Badge: pops in over the first 25 % with a slight overshoot, fades over
  // the last 20 %.
  late final Animation<double> _badgeScale = _c.drive(
    CurveTween(curve: const Interval(0, 0.25, curve: Curves.easeOutBack)),
  );
  late final Animation<double> _badgeOpacity = _c.drive(
    TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 70),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]),
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone?.call();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _ConfettiPainter(_c, _particles)),
            Center(
              child: FadeTransition(
                opacity: _badgeOpacity,
                child: ScaleTransition(
                  scale: _badgeScale,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(blurRadius: 18, color: Colors.black26),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: scheme.onPrimary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.label,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: scheme.onPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.angle,
    required this.speed,
    required this.spin,
    required this.color,
    required this.size,
  });

  /// Up-and-out cone from the centre, with gravity pulling pieces back down.
  static List<_Particle> burst(int seed, {int count = 40}) {
    final r = Random(seed);
    const colors = [
      Color(0xFFFBBF24),
      Color(0xFF14B8A6),
      Color(0xFFF43F5E),
      Color(0xFF8B5CF6),
      Color(0xFF38BDF8),
    ];
    return [
      for (var i = 0; i < count; i++)
        _Particle(
          angle: -pi / 2 + (r.nextDouble() - 0.5) * pi * 0.9,
          speed: 700 + r.nextDouble() * 600,
          spin: (r.nextDouble() - 0.5) * 12,
          color: colors[i % colors.length],
          size: Size(6 + r.nextDouble() * 5, 10 + r.nextDouble() * 6),
        ),
    ];
  }

  final double angle;
  final double speed; // px/s
  final double spin; // rad/s
  final Color color;
  final Size size;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.animation, this.particles) : super(repaint: animation);

  final Animation<double> animation;
  final List<_Particle> particles;

  static const _gravity = 1800.0; // px/s²

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * CelebrationBurst.duration.inMilliseconds / 1000;
    final fade = (1 - (animation.value - 0.7) / 0.3).clamp(0.0, 1.0);
    final origin = size.center(Offset.zero);
    final paint = Paint();
    for (final p in particles) {
      final pos =
          origin +
          Offset(
            cos(p.angle) * p.speed * t,
            sin(p.angle) * p.speed * t + 0.5 * _gravity * t * t,
          );
      paint.color = p.color.withValues(alpha: fade);
      canvas
        ..save()
        ..translate(pos.dx, pos.dy)
        ..rotate(p.spin * t)
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size.width,
              height: p.size.height,
            ),
            const Radius.circular(2),
          ),
          paint,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
