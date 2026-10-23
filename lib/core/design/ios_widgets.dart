import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'glean_colors.dart';

/// Press feedback in the iOS idiom: the child shrinks a little while held
/// and springs back on release (no ink ripple).
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
    reverseDuration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _scale =
      Tween(begin: 1.0, end: widget.pressedScale).animate(
        CurvedAnimation(
          parent: _c,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeOutBack,
        ),
      );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _c.forward(),
      onTapUp: (_) => _c.reverse(),
      onTapCancel: () => _c.reverse(),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

/// Frosted translucent surface (navigation bars, tab bar, floating controls).
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.color = const Color(0xC7F9F9FB),
    this.borderRadius = BorderRadius.zero,
    this.blur = 22,
  });

  final Widget child;
  final Color color;
  final BorderRadius borderRadius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: ColoredBox(color: color, child: child),
      ),
    );
  }
}

/// Large title block: small eyebrow line, 34 pt title, optional trailing.
class LargeTitle extends StatelessWidget {
  const LargeTitle({
    super.key,
    required this.title,
    this.eyebrow,
    this.trailing,
  });

  final String title;
  final String? eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null)
            Text(
              eyebrow!,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.displaySmall)),
              ?trailing,
            ],
          ),
        ],
      ),
    );
  }
}

/// Section title (22 pt bold) with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Rounded white inset group, like iOS Settings. [children] are separated by
/// hairlines inset by [dividerIndent].
class InsetGroup extends StatelessWidget {
  const InsetGroup({
    super.key,
    required this.children,
    this.dividerIndent = 16,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<Widget> children;
  final double dividerIndent;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ColoredBox(
          color: GleanColors.card,
          child: Column(
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0) Hairline(indent: dividerIndent),
                child,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class Hairline extends StatelessWidget {
  const Hairline({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: const SizedBox(
        height: 0.5,
        width: double.infinity,
        child: ColoredBox(color: GleanColors.separator),
      ),
    );
  }
}

/// Coloured difficulty pill: 初级 green, 中级 blue, 高级 amber.
class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.level, required this.label});

  final int level;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (bg, ink) =
        GleanColors.levelBadge[level] ??
        (GleanColors.fill2, GleanColors.label2);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
      ),
    );
  }
}

/// iOS sliding segmented control with the system look.
class IosSegmented<T extends Object> extends StatelessWidget {
  const IosSegmented({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        backgroundColor: GleanColors.fill,
        thumbColor: CupertinoColors.white,
        padding: const EdgeInsets.all(2),
        onValueChanged: (v) {
          if (v != null) onChanged(v);
        },
        children: {
          for (final e in items.entries)
            e.key: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                e.value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: GleanColors.label,
                ),
              ),
            ),
        },
      ),
    );
  }
}

/// Rounded grey search field.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.hint,
    this.controller,
    this.onChanged,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: GleanColors.fill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.search_rounded, size: 20, color: GleanColors.label2),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 16, color: GleanColors.label),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  fontSize: 16,
                  color: GleanColors.label2,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular avatar with a gradient and an initial.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({
    super.key,
    required this.initial,
    this.size = 36,
    this.colors = const [Color(0xFF99F6E4), GleanColors.tint],
  });

  final String initial;
  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
