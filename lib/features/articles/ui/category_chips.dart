import 'package:flutter/material.dart';

import '../../../core/design/glean_colors.dart';

/// Category tabs as capsules. The selected pill slides to the tapped tab with
/// a slight overshoot (easeOutBack), the label colours cross-fade.
///
/// Every label is two characters, so tabs share one width and the pill's
/// position is simply `index * (width + gap)`; no layout measuring needed.
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  // Six tabs fit a 390 pt wide screen without scrolling.
  static const chipWidth = 56.0;
  static const chipHeight = 34.0;
  static const gap = 5.0;
  static const slide = Duration(milliseconds: 420);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: chipHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          SizedBox(
            width: labels.length * (chipWidth + gap) - gap,
            child: Stack(
              children: [
                AnimatedPositioned(
                  key: const Key('chip-indicator'),
                  duration: slide,
                  curve: Curves.easeOutBack,
                  left: selected * (chipWidth + gap),
                  top: 0,
                  width: chipWidth,
                  height: chipHeight,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: GleanColors.label,
                      borderRadius: BorderRadius.all(
                        Radius.circular(chipHeight / 2),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final (i, label) in labels.indexed) ...[
                      if (i > 0) const SizedBox(width: gap),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelected(i),
                        child: SizedBox(
                          width: chipWidth,
                          height: chipHeight,
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: i == selected
                                    ? Colors.white
                                    : GleanColors.label2,
                              ),
                              child: Text(label),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
