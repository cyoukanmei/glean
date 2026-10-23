import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Save-to-word-list button whose bookmark squashes, overshoots and settles
/// whenever [collected] flips, while the icon morphs outline -> filled.
///
/// The parent flips [collected] optimistically on tap, so the bounce starts
/// on the same frame as the touch instead of after the database write.
class CollectButton extends StatefulWidget {
  const CollectButton({
    super.key,
    required this.collected,
    required this.onPressed,
  });

  final bool collected;
  final VoidCallback? onPressed;

  /// 1 -> 0.8 (80 ms, press) -> 1.25 (140 ms, overshoot) -> 1 (180 ms).
  static const bounce = Duration(milliseconds: 400);

  @override
  State<CollectButton> createState() => _CollectButtonState();
}

class _CollectButtonState extends State<CollectButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: CollectButton.bounce,
    value: 1,
  );

  late final Animation<double> _scale = _c.drive(
    TweenSequence([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.8,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 80,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.8,
          end: 1.25,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 140,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.25,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 180,
      ),
    ]),
  );

  @override
  void didUpdateWidget(CollectButton old) {
    super.didUpdateWidget(old);
    if (old.collected != widget.collected) {
      _c.forward(from: 0);
      if (widget.collected) HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const amber = Color(0xFFF59E0B);
    return FilledButton.tonal(
      onPressed: widget.onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            key: const Key('collect-icon-scale'),
            scale: _scale,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                widget.collected
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                key: ValueKey(widget.collected),
                color: widget.collected ? amber : scheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(widget.collected ? '已收藏' : '收藏到生词本'),
        ],
      ),
    );
  }
}
