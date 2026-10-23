import 'dart:async';

import 'package:english_reader/app/providers.dart';
import 'package:english_reader/core/widgets/shimmer.dart';
import 'package:english_reader/core/widgets/stagger_in.dart';
import 'package:english_reader/features/articles/data/article_repository.dart';
import 'package:english_reader/features/articles/ui/article_card.dart';
import 'package:english_reader/features/articles/ui/article_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Repository whose reads complete only when the test says so.
class _ControlledRepo implements ArticleRepository {
  final pending = <Completer<List<ArticleSummary>>>[];

  @override
  Future<List<ArticleSummary>> page({
    String? category,
    Set<int> levels = const {},
    FeedCursor? after,
    int limit = 10,
  }) {
    final c = Completer<List<ArticleSummary>>();
    pending.add(c);
    return c.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<ArticleSummary> _articles(int n) => [
  for (var i = 0; i < n; i++)
    ArticleSummary(
      id: 'a$i',
      title: 'Article $i',
      summary: 'Summary $i',
      cover: 'g${i % 8}',
      category: 'tech',
      level: 1,
      wordCount: 100,
      publishedAt: 1000 - i,
    ),
];

Future<_ControlledRepo> _pumpFeed(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = _ControlledRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        articleRepositoryProvider.overrideWithValue(repo),
        onlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: ArticleFeed(category: null)),
      ),
    ),
  );
  return repo;
}

void main() {
  testWidgets('a fast load never shows the skeleton', (tester) async {
    final repo = await _pumpFeed(tester);

    await tester.pump(const Duration(milliseconds: 80));
    repo.pending.single.complete(_articles(3));
    await tester.pump();

    expect(find.byType(Shimmer), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(Shimmer), findsNothing);
    expect(find.byType(ArticleCard), findsNWidgets(3));
    await tester.pumpAndSettle();
  });

  testWidgets('a slow load shows the skeleton for at least 400 ms', (
    tester,
  ) async {
    final repo = await _pumpFeed(tester);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Shimmer), findsNothing);
    await tester.pump(const Duration(milliseconds: 40)); // past 120 ms
    expect(find.byType(Shimmer), findsOneWidget);

    // Data arrives 50 ms after the skeleton appeared...
    await tester.pump(const Duration(milliseconds: 50));
    repo.pending.single.complete(_articles(3));
    await tester.pump();
    // ...but the skeleton stays until 400 ms have passed.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Shimmer), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(Shimmer), findsNothing);
    expect(find.byType(ArticleCard), findsNWidgets(3));
    await tester.pumpAndSettle();
  });

  testWidgets('a slow reload after a filter change shows a visible skeleton', (
    tester,
  ) async {
    final repo = await _pumpFeed(tester);
    repo.pending.single.complete(_articles(3));
    await tester.pumpAndSettle();

    ProviderScope.containerOf(
      tester.element(find.byType(ArticleFeed)),
    ).read(levelFilterProvider.notifier).toggle(3);
    await tester.pump();
    // Old list fades out (120 ms), then the reload waits 120 ms more.
    await tester.pump(const Duration(milliseconds: 130));
    await tester.pump(const Duration(milliseconds: 130));

    expect(find.byType(Shimmer), findsOneWidget);
    final opacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byType(Shimmer),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(opacity.opacity, 1);

    repo.pending.last.complete(_articles(2));
    await tester.pumpAndSettle();
    expect(find.byType(ArticleCard), findsNWidgets(2));
  });

  testWidgets('the first screen cascades in; later items do not animate', (
    tester,
  ) async {
    final repo = await _pumpFeed(tester);
    repo.pending.single.complete(_articles(10));
    await tester.pump();

    expect(find.byType(StaggerIn), findsWidgets);
    double opacityOf(int i) => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.text('Article $i'),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

    // 100 ms in: the first item is well on its way, the fifth has not
    // started (it begins at 4 x 40 = 160 ms).
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacityOf(0), greaterThan(0.3));
    expect(opacityOf(4), 0);

    await tester.pump(StaggerIn.totalDuration);
    expect(opacityOf(0), 1);
    expect(opacityOf(4), 1);
    await tester.pumpAndSettle();
  });
}
