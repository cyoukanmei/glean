import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';

/// Colours of one reader theme, interpolable so a theme switch cross-fades
/// instead of snapping.
@immutable
class ReaderPalette {
  const ReaderPalette({
    required this.background,
    required this.text,
    required this.title,
    required this.secondary,
    required this.accent,
    required this.chipBg,
    required this.bar,
    required this.barInk,
  });

  ReaderPalette.of(ReaderTheme t)
    : this(
        background: t.background,
        text: t.text,
        title: t.title,
        secondary: t.secondary,
        accent: t.accent,
        chipBg: t.chipBg,
        bar: t.bar,
        barInk: t.barInk,
      );

  final Color background;
  final Color text;
  final Color title;
  final Color secondary;
  final Color accent;
  final Color chipBg;
  final Color bar;
  final Color barInk;

  static ReaderPalette lerp(ReaderPalette a, ReaderPalette b, double t) =>
      ReaderPalette(
        background: Color.lerp(a.background, b.background, t)!,
        text: Color.lerp(a.text, b.text, t)!,
        title: Color.lerp(a.title, b.title, t)!,
        secondary: Color.lerp(a.secondary, b.secondary, t)!,
        accent: Color.lerp(a.accent, b.accent, t)!,
        chipBg: Color.lerp(a.chipBg, b.chipBg, t)!,
        bar: Color.lerp(a.bar, b.bar, t)!,
        barInk: Color.lerp(a.barInk, b.barInk, t)!,
      );
}

class ReaderPaletteTween extends Tween<ReaderPalette> {
  ReaderPaletteTween({super.begin, super.end});

  @override
  ReaderPalette lerp(double t) => ReaderPalette.lerp(begin!, end!, t);
}

/// Round frosted button floating over the article (back, Aa, share).
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.palette,
    required this.label,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final ReaderPalette palette;
  final String label;

  static const size = 38.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.9,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 10)],
          ),
          child: Glass(
            color: palette.bar,
            blur: 18,
            borderRadius: BorderRadius.circular(size / 2),
            child: SizedBox.square(
              dimension: size,
              child: Icon(icon, size: 20, color: palette.barInk),
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating capsule at the bottom: previous article, progress, next article.
class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.progress,
    required this.palette,
    required this.onPrevious,
    required this.onNext,
  });

  final ValueListenable<double> progress;
  final ReaderPalette palette;

  /// Null when there is no article in that direction.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  static const height = 56.0;

  @override
  Widget build(BuildContext context) {
    Widget nav(IconData icon, VoidCallback? onTap, String key, String label) =>
        Semantics(
          button: true,
          label: label,
          child: PressableScale(
            key: Key(key),
            onTap: onTap,
            pressedScale: 0.88,
            child: SizedBox.square(
              dimension: 44,
              child: AnimatedOpacity(
                opacity: onTap == null ? 0.3 : 1,
                duration: const Duration(milliseconds: 200),
                child: Icon(icon, color: palette.barInk),
              ),
            ),
          ),
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E000000),
            blurRadius: 30,
            offset: Offset(0, 10),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Glass(
        color: palette.bar,
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                nav(
                  Icons.chevron_left_rounded,
                  onPrevious,
                  'reader-prev',
                  '上一篇',
                ),
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: progress,
                    builder: (context, v, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 40,
                          child: Text(
                            '${(v * 100).round()}%',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: palette.secondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 96,
                          height: 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(end: v),
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              builder: (context, w, _) =>
                                  LinearProgressIndicator(
                                    value: w,
                                    minHeight: 4,
                                    color: palette.accent,
                                    backgroundColor: palette.secondary
                                        .withValues(alpha: 0.18),
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '下一篇',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: palette.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                nav(Icons.chevron_right_rounded, onNext, 'reader-next', '下一篇'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
