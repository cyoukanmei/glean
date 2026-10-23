import 'package:flutter/services.dart';

final _letters = RegExp('[A-Za-z]+');

/// Narrows a word boundary from text layout (Unicode word rules, which may
/// include apostrophes or stray punctuation) to the run of letters the
/// dictionary can look up: `parent's` -> `parent`, `"Hello,` -> `Hello`.
///
/// Prefers the run under [tapOffset]; returns null when there are no
/// letters (a tap on a number or punctuation).
TextRange? letterRange(String text, TextRange boundary, {int? tapOffset}) {
  if (!boundary.isValid || boundary.isCollapsed) return null;
  final slice = text.substring(boundary.start, boundary.end);
  TextRange? first;
  for (final m in _letters.allMatches(slice)) {
    final r = TextRange(
      start: boundary.start + m.start,
      end: boundary.start + m.end,
    );
    first ??= r;
    if (tapOffset != null && tapOffset >= r.start && tapOffset < r.end) {
      return r;
    }
  }
  return first;
}

/// The sentence of [text] that contains [range], for a word's example line.
///
/// A sentence ends at `.`, `!` or `?` followed by whitespace (or the end of
/// the paragraph), so "Mr. Smith" style abbreviations may split early; good
/// enough for a context line.
String sentenceAround(String text, TextRange range) {
  bool endsSentence(int i) =>
      '.!?'.contains(text[i]) &&
      (i + 1 == text.length || text[i + 1].trim().isEmpty);

  var start = range.start;
  while (start > 0 && !endsSentence(start - 1)) {
    start--;
  }
  var end = range.end;
  while (end < text.length && !endsSentence(end)) {
    end++;
  }
  if (end < text.length) end++; // keep the closing punctuation
  return text.substring(start, end).trim();
}

/// Letter runs of [text] as ranges, for marking collected words.
Iterable<TextRange> wordRanges(String text) =>
    _letters.allMatches(text).map((m) => TextRange(start: m.start, end: m.end));
