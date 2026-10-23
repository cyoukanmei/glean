import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../vocab/application/word_picking.dart';

/// One paragraph of article text that can be long-pressed to pick a word.
///
/// Marks words three ways: the word being looked up ([selected]), words
/// already in the word list ([collected], dotted underline) and a word the
/// reader jumped back to from the word list ([pulse], flashing background).
class ReaderParagraph extends StatefulWidget {
  const ReaderParagraph({
    super.key,
    required this.text,
    required this.style,
    required this.collected,
    required this.onWord,
    this.selected,
    this.pulse,
  });

  final String text;
  final TextStyle? style;

  /// Lower-cased forms whose occurrences get the "already saved" underline.
  final Set<String> collected;
  final TextRange? selected;

  /// Range to flash, and the 0..1 opacity driving the flash.
  final (TextRange, Animation<double>)? pulse;

  /// Long-press landed on a word; [range] covers its letters.
  final void Function(TextRange range) onWord;

  @override
  State<ReaderParagraph> createState() => _ReaderParagraphState();
}

class _ReaderParagraphState extends State<ReaderParagraph> {
  final _textKey = GlobalKey();

  void _onLongPress(LongPressStartDetails d) {
    final box = _textKey.currentContext?.findRenderObject();
    if (box is! RenderParagraph) return;
    // The detector wraps the text exactly, so its local position is the
    // paragraph's own coordinate space.
    final position = box.getPositionForOffset(d.localPosition);
    final range = letterRange(
      widget.text,
      box.getWordBoundary(position),
      tapOffset: position.offset,
    );
    if (range != null) widget.onWord(range);
  }

  @override
  Widget build(BuildContext context) {
    final pulse = widget.pulse;
    Widget text(double pulseOpacity) => Text.rich(
      key: _textKey,
      _spans(context, pulseOpacity),
      style: widget.style,
    );
    return GestureDetector(
      onLongPressStart: _onLongPress,
      child: pulse == null
          ? text(0)
          : AnimatedBuilder(
              animation: pulse.$2,
              builder: (context, _) => text(pulse.$2.value),
            ),
    );
  }

  TextSpan _spans(BuildContext context, double pulseOpacity) {
    final scheme = Theme.of(context).colorScheme;
    final t = widget.text;
    final children = <TextSpan>[];
    var at = 0;
    for (final r in wordRanges(t)) {
      final isSelected = r == widget.selected;
      final isPulse = widget.pulse?.$1 == r && pulseOpacity > 0;
      final isCollected = widget.collected.contains(
        t.substring(r.start, r.end).toLowerCase(),
      );
      if (!isSelected && !isPulse && !isCollected) continue;
      if (r.start > at) children.add(TextSpan(text: t.substring(at, r.start)));
      children.add(
        TextSpan(
          text: t.substring(r.start, r.end),
          style: TextStyle(
            backgroundColor: isSelected
                ? scheme.primaryContainer
                : isPulse
                ? const Color(0xFFFBBF24).withValues(alpha: 0.55 * pulseOpacity)
                : null,
            decoration: isCollected ? TextDecoration.underline : null,
            decorationStyle: TextDecorationStyle.dotted,
            decorationColor: scheme.primary,
            decorationThickness: 2,
          ),
        ),
      );
      at = r.end;
    }
    if (at < t.length) children.add(TextSpan(text: t.substring(at)));
    return TextSpan(children: children);
  }
}
