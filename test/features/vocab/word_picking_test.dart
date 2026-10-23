import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/features/vocab/application/word_picking.dart';

TextRange _range(String text, String word) {
  final i = text.indexOf(word);
  return TextRange(start: i, end: i + word.length);
}

String _cut(String text, TextRange? r) => text.substring(r!.start, r.end);

void main() {
  group('letterRange', () {
    test('drops possessive and punctuation', () {
      const text = 'My parent\'s bike, "Hello," she said.';
      expect(_cut(text, letterRange(text, _range(text, "parent's"))), 'parent');
      expect(_cut(text, letterRange(text, _range(text, '"Hello,'))), 'Hello');
    });

    test('prefers the run under the finger', () {
      const text = 'well-known';
      final whole = _range(text, text);
      final r = letterRange(text, whole, tapOffset: text.indexOf('known') + 1);
      expect(_cut(text, r), 'known');
    });

    test('null for numbers, punctuation and empty boundaries', () {
      const text = 'In 2026, yes.';
      expect(letterRange(text, _range(text, '2026')), isNull);
      expect(letterRange(text, _range(text, ',')), isNull);
      expect(letterRange(text, const TextRange.collapsed(3)), isNull);
    });
  });

  group('sentenceAround', () {
    const text =
        'Batteries age. Heat makes it worse! Do you charge overnight? '
        'Most phones now slow down near full';

    test('finds the containing sentence with its punctuation', () {
      expect(
        sentenceAround(text, _range(text, 'worse')),
        'Heat makes it worse!',
      );
      expect(sentenceAround(text, _range(text, 'Batteries')), 'Batteries age.');
      expect(
        sentenceAround(text, _range(text, 'overnight')),
        'Do you charge overnight?',
      );
    });

    test('the last sentence may lack a full stop', () {
      expect(
        sentenceAround(text, _range(text, 'slow')),
        'Most phones now slow down near full',
      );
    });

    test('a dot inside a number does not split', () {
      const t = 'It costs 2.5 dollars today. Fine.';
      expect(
        sentenceAround(t, _range(t, 'dollars')),
        'It costs 2.5 dollars today.',
      );
    });
  });

  test('wordRanges lists letter runs only', () {
    const t = "It's 9 a.m.";
    expect(wordRanges(t).map((r) => t.substring(r.start, r.end)).toList(), [
      'It',
      's',
      'a',
      'm',
    ]);
  });
}
