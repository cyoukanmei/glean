import 'package:flutter/material.dart';

/// Fades and lifts a list item in, offset by its [index] on a shared
/// [animation], so the first screen of a list cascades in instead of
/// flashing in all at once.
///
/// Item i runs from `i * step` to `i * step + itemDuration` of the parent
/// animation; with 8 items, 40 ms steps and 300 ms each, the whole cascade
/// takes [totalDuration] = 580 ms.
class StaggerIn extends StatelessWidget {
  const StaggerIn({
    super.key,
    required this.animation,
    required this.index,
    required this.child,
  });

  final Animation<double> animation;
  final int index;
  final Widget child;

  static const maxItems = 8;
  static const step = Duration(milliseconds: 40);
  static const itemDuration = Duration(milliseconds: 300);
  static final totalDuration = step * (maxItems - 1) + itemDuration;
  static const rise = 16.0;

  @override
  Widget build(BuildContext context) {
    final total = totalDuration.inMicroseconds;
    final start = step.inMicroseconds * index / total;
    final end = (start + itemDuration.inMicroseconds / total).clamp(0.0, 1.0);
    // drive() only listens to the parent while something listens to it, so
    // rebuilding this widget does not leak listeners.
    final t = animation.drive(
      CurveTween(curve: Interval(start, end, curve: Curves.easeOutCubic)),
    );
    return FadeTransition(
      opacity: t,
      child: AnimatedBuilder(
        animation: t,
        child: child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, rise * (1 - t.value)),
          child: child,
        ),
      ),
    );
  }
}
