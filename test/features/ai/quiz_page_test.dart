import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/app/providers.dart';
import 'package:glean/features/ai/data/ai_repository.dart';
import 'package:glean/features/ai/ui/quiz_page.dart';
import 'package:glean/features/articles/data/article_repository.dart';

import '../../helpers/fakes.dart';

const _article = ArticleSummary(
  id: 'a1',
  title: 'Why We Put Things Off',
  summary: '',
  cover: 'g0',
  category: 'daily',
  level: 3,
  wordCount: 400,
  publishedAt: 0,
);

QuizQuestion _q(String text, int answer) => QuizQuestion(
  type: 'detail',
  question: text,
  options: const ['first', 'second', 'third', 'fourth'],
  answer: answer,
  explainZh: '解析 $text',
);

final _ai = ArticleAi(
  summaryZh: '摘要',
  keyPoints: const ['要点'],
  cefr: 'B2',
  cefrReason: '理由',
  questions: [_q('Q one?', 1), _q('Q two?', 3)],
);

void main() {
  testWidgets('a pick locks the question, shows the answer and the '
      'explanation; the score is saved at the end', (tester) async {
    final repo = FakeAiRepository(_ai);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [aiRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: QuizPage(article: _article, ai: _ai),
        ),
      ),
    );

    expect(find.text('Q one?'), findsOneWidget);
    expect(find.byKey(const Key('quiz-explain')), findsNothing);

    // Right answer.
    await tester.tap(find.byKey(const Key('quiz-option-1')));
    await tester.pumpAndSettle();
    expect(find.text('答对了'), findsOneWidget);
    expect(find.text('解析 Q one?'), findsOneWidget);
    // Locked: another tap changes nothing.
    await tester.tap(find.byKey(const Key('quiz-option-2')));
    await tester.pumpAndSettle();
    expect(find.text('答对了'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quiz-next')));
    await tester.pumpAndSettle();
    expect(find.text('Q two?'), findsOneWidget);

    // Wrong answer: the right one is named.
    await tester.tap(find.byKey(const Key('quiz-option-0')));
    await tester.pumpAndSettle();
    expect(find.text('正确答案是 D'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quiz-next')));
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    expect(repo.results['a1'], [1, 0]);
  });
}
