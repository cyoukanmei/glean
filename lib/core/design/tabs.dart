import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glean_colors.dart';

/// Primary switch between views of a page (推荐 / 最新 / 我的, categories):
/// plain text, the selected label larger and bold, with a short bar under it
/// that slides over with a slight overshoot.
///
/// Labels are measured once with the selected style, so the row never
/// reflows while the label grows. Scrolls sideways when it does not fit.
class TextTabs extends StatelessWidget {
  const TextTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.fontSize = 15.5,
    this.gap = 22,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.trailing,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final double fontSize;
  final double gap;
  final EdgeInsets padding;

  /// Pinned at the right end (e.g. "完整榜单 ›").
  final Widget? trailing;

  static const height = 36.0;
  static const barWidth = 16.0;
  static const slide = Duration(milliseconds: 380);

  TextStyle get _selectedStyle => TextStyle(
    fontSize: fontSize + 2,
    fontWeight: FontWeight.w700,
    color: GleanColors.label,
    letterSpacing: -0.2,
  );

  TextStyle get _style => TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w500,
    color: GleanColors.label2,
  );

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final widths = [
      for (final l in labels)
        (TextPainter(
          text: TextSpan(text: l, style: _selectedStyle),
          textDirection: TextDirection.ltr,
          textScaler: scale,
          maxLines: 1,
        )..layout()).width.ceilToDouble(),
    ];
    var left = 0.0;
    final lefts = <double>[];
    for (final w in widths) {
      lefts.add(left);
      left += w + gap;
    }
    final total = left - gap;
    final barLeft = lefts[selected] + widths[selected] / 2 - barWidth / 2;

    final row = SizedBox(
      width: total,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final (i, label) in labels.indexed)
            Positioned(
              left: lefts[i],
              width: widths[i],
              top: 0,
              bottom: 8,
              child: Semantics(
                selected: i == selected,
                button: true,
                child: GestureDetector(
                  key: Key('text-tab-$i'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (i == selected) return;
                    HapticFeedback.selectionClick();
                    onSelected(i);
                  },
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      style: i == selected ? _selectedStyle : _style,
                      child: Text(label, maxLines: 1, softWrap: false),
                    ),
                  ),
                ),
              ),
            ),
          AnimatedPositioned(
            key: const Key('text-tab-bar'),
            duration: slide,
            curve: Curves.easeOutBack,
            left: barLeft,
            width: barWidth,
            bottom: 1,
            height: 3.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: GleanColors.tint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );

    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: padding,
              child: row,
            ),
          ),
          if (trailing case final t?)
            Padding(
              padding: EdgeInsets.only(right: padding.right),
              child: t,
            ),
        ],
      ),
    );
  }
}

/// Secondary filter as a row of capsules (全部 46 · 新词 12 · 认识 30): the
/// selected one is solid ink with white text, the others are light pills.
/// Optional counts sit after the label in a lighter weight.
///
/// [expand] shares the width equally (settings choices); otherwise the row
/// scrolls sideways.
class PillTabs<T extends Object> extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.counts = const {},
    this.expand = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final T value;
  final Map<T, String> items;
  final Map<T, int> counts;
  final ValueChanged<T> onChanged;
  final bool expand;
  final EdgeInsets padding;

  static const height = 34.0;

  @override
  Widget build(BuildContext context) {
    final pills = [
      for (final MapEntry(:key, value: label) in items.entries)
        _Pill(
          key: Key('pill-$key'),
          label: label,
          count: counts[key],
          selected: key == value,
          onTap: () {
            if (key == value) return;
            HapticFeedback.selectionClick();
            onChanged(key);
          },
        ),
    ];
    if (expand) {
      return Padding(
        padding: padding,
        child: Row(
          children: [
            for (final (i, p) in pills.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: p),
            ],
          ],
        ),
      );
    }
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: pills.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => pills[i],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? GleanColors.background : GleanColors.label2;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: PillTabs.height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? GleanColors.label : GleanColors.field,
            borderRadius: BorderRadius.circular(PillTabs.height / 2),
            border: Border.all(
              color: selected || GleanColors.cardShadow.isEmpty
                  ? Colors.transparent
                  : GleanColors.separator,
              width: 0.5,
            ),
          ),
          child: Text.rich(
            TextSpan(
              text: label,
              children: [
                if (count case final n?)
                  TextSpan(
                    text: ' $n',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: ink.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: ink,
            ),
          ),
        ),
      ),
    );
  }
}
