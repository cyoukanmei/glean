import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/app/providers.dart';
import 'package:glean/core/navigation/swipe_back_route.dart';
import 'package:glean/features/articles/data/article_repository.dart';
import 'package:glean/features/reader/ui/reader_page.dart';

class _Repo implements ArticleRepository {
  @override
  Future<List<String>> paragraphs(String id) async => ['First.', 'Second.'];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _article = ArticleSummary(
  id: 'a1',
  title: 'A Title',
  summary: 'S',
  cover: 'g0',
  category: 'tech',
  level: 1,
  wordCount: 2,
  publishedAt: 0,
);

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [articleRepositoryProvider.overrideWithValue(_Repo())],
      child: MaterialApp(
        onGenerateRoute: (settings) => SwipeBackPageRoute<void>(
          settings: settings,
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                SwipeBackPageRoute<void>(
                  builder: (_) =>
                      const ReaderPage(article: _article, surface: 'all'),
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
}

double _bodyOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(find.byKey(const Key('reader-body')))
    .opacity
    .value;

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

    await tester.pumpAndSettle();
    expect(_bodyOpacity(tester), 1);
    expect(find.text('Second.'), findsOneWidget);
  });

  testWidgets('a cancelled swipe-back does not replay the entrance', (
    tester,
  ) async {
    await _open(tester);
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    expect(find.text('A Title'), findsOneWidget);
  });
}
