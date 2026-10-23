import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/app/providers.dart';
import 'package:glean/features/vocab/data/vocab_repository.dart';
import 'package:glean/features/vocab/ui/review_page.dart';

import '../../helpers/fakes.dart';

VocabItem _item(String id, String word) => VocabItem(
  id: id,
  word: word,
  lemma: word,
  definition: 'n. 释义 $word',
  source: WordSource(
    articleId: 'a1',
    paraIndex: 0,
    charStart: 0,
    charEnd: word.length,
    sentence: 'The $word is here.',
  ),
  status: VocabStatus.fresh,
  createdAt: 1,
  articleTitle: 'A Title',
);

void main() {
  testWidgets('known words move on at once; 不认识 flips to the meaning '
      'first, then 下一个 moves on', (tester) async {
    final vocab = FakeVocabRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [vocabRepositoryProvider.overrideWithValue(vocab)],
        child: MaterialApp(
          home: ReviewPage(items: [_item('v1', 'lantern'), _item('v2', 'tea')]),
        ),
      ),
    );

    expect(find.text('lantern'), findsOneWidget);
    // The buttons are there on the front; tapping the card does nothing.
    await tester.tap(find.text('lantern'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('释义 lantern', findRichText: true),
      findsNothing,
      reason: 'still the front',
    );
    await tester.tap(find.byKey(const Key('rate-2')));
    await tester.pumpAndSettle();
    expect(vocab.statuses, {'v1': VocabStatus.mastered});
    expect(find.text('tea'), findsOneWidget, reason: 'next card, not flipped');

    await tester.tap(find.byKey(const Key('rate-0')));
    await tester.pumpAndSettle();
    expect(vocab.statuses['v2'], VocabStatus.fresh);
    expect(find.textContaining('释义 tea', findRichText: true), findsOneWidget);
    expect(find.byKey(const Key('rate-1')), findsNothing);
    await tester.tap(find.byKey(const Key('review-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review-done')), findsOneWidget);
  });
}
