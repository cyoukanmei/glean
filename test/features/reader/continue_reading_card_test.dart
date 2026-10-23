import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/app/providers.dart';
import 'package:glean/core/design/progress_ring.dart';
import 'package:glean/features/articles/data/article_repository.dart';
import 'package:glean/features/reader/ui/continue_reading_card.dart';

import '../../helpers/fakes.dart';

class _Repo implements ArticleRepository {
  @override
  Future<ArticleSummary?> byId(String id) async => ArticleSummary(
    id: id,
    title: 'Half-read article',
    summary: '',
    cover: 'g2',
    category: 'culture',
    level: 2,
    wordCount: 300,
    publishedAt: 0,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeProgressRepository progress,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        articleRepositoryProvider.overrideWithValue(_Repo()),
        progressRepositoryProvider.overrideWithValue(progress),
      ],
      child: const MaterialApp(home: Scaffold(body: ContinueReadingCard())),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(
    tester.element(find.byType(ContinueReadingCard)),
  );
}

void main() {
  testWidgets('hidden when nothing is in progress', (tester) async {
    await _pump(tester, FakeProgressRepository());
    await tester.pumpAndSettle();
    expect(find.textContaining('继续阅读'), findsNothing);
  });

  testWidgets('ring glides from 0 to the saved progress', (tester) async {
    await _pump(
      tester,
      FakeProgressRepository(unfinished: ('a1', progressAt(0, progress: 0.63))),
    );
    await tester.pump();
    expect(find.text('Half-read article'), findsOneWidget);

    await tester.pump(ContinueReadingCard.barGlide ~/ 4);
    final mid = tester.widget<ProgressRing>(find.byType(ProgressRing)).value;
    expect(mid, greaterThan(0));
    expect(mid, lessThan(0.63));

    await tester.pumpAndSettle();
    expect(find.text('63%'), findsOneWidget);
  });

  testWidgets('reloads and pushes forward after the reader saves', (
    tester,
  ) async {
    final progress = FakeProgressRepository(
      unfinished: ('a1', progressAt(0, progress: 0.3)),
    );
    final container = await _pump(tester, progress);
    await tester.pumpAndSettle();
    expect(find.text('30%'), findsOneWidget);

    progress.unfinished = ('a1', progressAt(0, progress: 0.8));
    container.read(progressRevisionProvider.notifier).bump();
    await tester.pumpAndSettle();
    expect(find.text('80%'), findsOneWidget);
  });
}
