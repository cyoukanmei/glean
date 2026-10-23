import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/app/providers.dart';
import 'package:glean/core/navigation/swipe_back_route.dart';
import 'package:glean/core/widgets/celebration.dart';
import 'package:glean/features/articles/data/article_repository.dart';
import 'package:glean/features/reader/ui/reader_page.dart';

import '../../helpers/fakes.dart';

class _Repo implements ArticleRepository {
  _Repo(this.paragraphCount);

  final int paragraphCount;

  @override
  Future<List<String>> paragraphs(String id) async => [
    for (var i = 0; i < paragraphCount; i++)
      'Paragraph $i. ${'Some reading text that wraps over lines. ' * 6}',
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ArticleSummary _article({int words = 2}) => ArticleSummary(
  id: 'a1',
  title: 'A Title',
  summary: 'S',
  cover: 'g0',
  category: 'tech',
  level: 1,
  wordCount: words,
  publishedAt: 0,
);

Future<FakeProgressRepository> _open(
  WidgetTester tester, {
  int paragraphs = 2,
  int words = 2,
  FakeProgressRepository? progress,
}) async {
  final repo = progress ?? FakeProgressRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        articleRepositoryProvider.overrideWithValue(_Repo(paragraphs)),
        progressRepositoryProvider.overrideWithValue(repo),
        readingTimeRepositoryProvider.overrideWithValue(
          FakeReadingTimeRepository(),
        ),
      ],
      child: MaterialApp(
        onGenerateRoute: (settings) => SwipeBackPageRoute<void>(
          settings: settings,
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                SwipeBackPageRoute<void>(
                  builder: (_) => ReaderPage(
                    article: _article(words: words),
                    surface: 'all',
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  return repo;
}

double _bodyOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(find.byKey(const Key('reader-body')))
    .opacity
    .value;

double _barFill(WidgetTester tester) => tester
    .widget<FractionallySizedBox>(
      find.byKey(const Key('reading-progress-fill')),
    )
    .widthFactor!;

ScrollPosition _scroll(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).last).position;

/// Renders frames for [d] (one pump would jump the clock in a single frame,
/// so chained animations would never get frames to run in).
Future<void> _run(WidgetTester tester, Duration d) async {
  for (var t = 0; t < d.inMilliseconds; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Leaves the reader so its periodic ticker stops before the test ends.
Future<void> _close(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator)).pop();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('body stays hidden during the transition, then fades in', (
    tester,
  ) async {
    await _open(tester);

    await tester.pump(const Duration(milliseconds: 200));
    expect(_bodyOpacity(tester), 0, reason: 'mid-transition');

    // Transition is 420 ms; the entrance starts 80 ms after it completes.
    await tester.pump(const Duration(milliseconds: 260));
    expect(_bodyOpacity(tester), 0, reason: 'inside the 80 ms pause');

    await tester.pump(ReaderPage.entranceDelay);
    await tester.pump(const Duration(milliseconds: 100));
    final mid = _bodyOpacity(tester);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));

    await _run(tester, const Duration(seconds: 1));
    expect(_bodyOpacity(tester), 1);
    await _close(tester);
  });

  testWidgets('a cancelled swipe-back does not replay the entrance', (
    tester,
  ) async {
    await _open(tester, paragraphs: 20, words: 2000);
    await _run(tester, const Duration(seconds: 1));
    expect(_bodyOpacity(tester), 1);

    final gesture = await tester.startGesture(const Offset(400, 300));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(_bodyOpacity(tester), 1);
    await gesture.up();

    // Springs back (200 px of 800 is under halfway); watch every frame.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(_bodyOpacity(tester), 1);
    }
    await _close(tester);
  });

  testWidgets('the progress bar follows scrolling', (tester) async {
    await _open(tester, paragraphs: 20, words: 2000);
    await _run(tester, const Duration(seconds: 1));
    final start = _barFill(tester);

    await tester.drag(find.byType(Scrollable).last, const Offset(0, -1500));
    await _run(tester, const Duration(seconds: 1));
    expect(_barFill(tester), greaterThan(start + 0.1));
    await _close(tester);
  });

  testWidgets('returns to the saved position and offers "回到开头"', (
    tester,
  ) async {
    final repo = FakeProgressRepository(saved: progressAt(900));
    await _open(tester, paragraphs: 20, words: 2000, progress: repo);
    await _run(tester, const Duration(seconds: 2));

    expect(_scroll(tester).pixels, moreOrLessEquals(900, epsilon: 1));
    expect(find.textContaining('已回到上次位置'), findsOneWidget);

    await tester.tap(find.text('回到开头'));
    await _run(tester, const Duration(seconds: 1));
    expect(_scroll(tester).pixels, 0);
    await _close(tester);
  });

  testWidgets('a fully read article celebrates once', (tester) async {
    // One paragraph fits on the 800x600 test screen; 2 words need 0.3 s.
    final repo = await _open(tester, paragraphs: 1);
    await _run(tester, const Duration(seconds: 2));

    expect(find.byType(CelebrationBurst), findsOneWidget);
    expect(repo.finishedCalls, 1);

    await _run(tester, CelebrationBurst.duration);
    await tester.pump();
    expect(find.byType(CelebrationBurst), findsNothing);

    await _run(tester, const Duration(seconds: 3));
    expect(repo.finishedCalls, 1, reason: 'never re-marked in one visit');
    await _close(tester);
  });

  testWidgets('an already finished article does not celebrate again', (
    tester,
  ) async {
    final repo = FakeProgressRepository(
      saved: progressAt(0, progress: 1, status: 2),
    );
    await _open(tester, paragraphs: 1, progress: repo);
    await _run(tester, const Duration(seconds: 2));
    expect(find.byType(CelebrationBurst), findsNothing);
    expect(repo.finishedCalls, 0);
    await _close(tester);
  });
}
