import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Thin bar along the top showing how much of the article has been seen.
///
/// Every new value is approached over [ease] instead of jumping, so scroll
/// updates read as a smooth push and restore jumps glide. Wrapped in its own
/// RepaintBoundary and driven by a ValueListenable, so scrolling repaints
/// only this strip, not the text.
class ReadingProgressBar extends StatelessWidget {
  const ReadingProgressBar({
    super.key,
    required this.progress,
    this.height = 3,
  });

  final ValueListenable<double> progress;
  final double height;

  static const ease = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        child: ValueListenableBuilder(
          valueListenable: progress,
          builder: (context, value, _) => TweenAnimationBuilder<double>(
            tween: Tween(end: value),
            duration: ease,
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                key: const Key('reading-progress-fill'),
                widthFactor: v.clamp(0.0, 1.0),
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
