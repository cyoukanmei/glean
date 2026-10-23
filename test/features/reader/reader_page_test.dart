import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/app/providers.dart';
import 'package:glean/core/navigation/swipe_back_route.dart';
import 'package:glean/core/widgets/celebration.dart';
import 'package:glean/core/widgets/collect_button.dart';
import 'package:glean/features/articles/data/article_repository.dart';
import 'package:glean/features/reader/ui/reader_page.dart';
import 'package:glean/features/reader/ui/reader_paragraph.dart';
import 'package:glean/features/reader/application/reader_settings.dart';
import 'package:glean/features/reader/ui/finish_card.dart';
import 'package:glean/features/vocab/data/vocab_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fakes.dart';

class _Repo implements ArticleRepository {
  _Repo(this.paragraphCount, {this.next});

  final int paragraphCount;

  /// Returned as the older neighbour (the "next" article).
  final ArticleSummary? next;

  @override
  Future<ArticleSummary?> neighbor(
    ArticleSummary article, {
    required bool newer,
  }) async => newer || article.id == next?.id ? null : next;

  @override
  Future<List<String>> paragraphs(String id) async => [
    for (var i = 0; i < paragraphCount; i++)
      'Paragraph $i. ${'Some reading text that wraps over lines. ' * 6}',
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ArticleSummary _article({int words = 2, String id = 'a1'}) => ArticleSummary(
  id: id,
  title: 'Title of $id',
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
  FakeVocabRepository? vocab,
  FakeDictionaryRepository? dictionary,
  WordSource? jumpTo,
  ArticleSummary? next,
}) async {
  final repo = progress ?? FakeProgressRepository();
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        articleRepositoryProvider.overrideWithValue(
          _Repo(paragraphs, next: next),
        ),
        progressRepositoryProvider.overrideWithValue(repo),
        readingTimeRepositoryProvider.overrideWithValue(
          FakeReadingTimeRepository(),
        ),
        vocabRepositoryProvider.overrideWithValue(
          vocab ?? FakeVocabRepository(),
        ),
        dictionaryRepositoryProvider.overrideWithValue(
          dictionary ?? FakeDictionaryRepository(),
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
                    jumpTo: jumpTo,
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

/// Screen centre of the first [word] in paragraph [index], from the laid-out
/// text, so a long-press lands exactly on it.
Offset _wordCenter(WidgetTester tester, int index, String word) {
  final paragraph = find.byType(ReaderParagraph).at(index);
  final text = tester.widget<ReaderParagraph>(paragraph).text;
  final render = tester.renderObject<RenderParagraph>(
    find.descendant(of: paragraph, matching: find.byType(RichText)),
  );
  final start = text.indexOf(word);
  final box = render
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + word.length),
      )
      .first;
  return render.localToGlobal(box.toRect().center);
}

/// The hint stays in the tree while hidden (it fades), so check its opacity.
bool _hintVisible(WidgetTester tester) =>
    tester
        .widget<AnimatedOpacity>(find.byKey(const Key('restore-hint')))
        .opacity ==
    1;

final _dictionary = FakeDictionaryRepository({'reading': ('read', 'v. 读，阅读')});

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
    expect(_hintVisible(tester), isTrue);

    await tester.tap(find.text('回到开头'));
    await _run(tester, const Duration(seconds: 1));
    expect(_scroll(tester).pixels, 0);
    await _close(tester);
  });

  testWidgets('a fully read article celebrates once', (tester) async {
    // A tall screen so cover + one paragraph fit; 2 words need 0.3 s.
    tester.view
      ..physicalSize = const Size(800, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = await _open(tester, paragraphs: 1);
    await _run(tester, const Duration(seconds: 2));

    expect(find.byType(CelebrationBurst), findsOneWidget);
    expect(repo.finishedCalls, 1);
    await _run(tester, const Duration(milliseconds: 500));
    expect(find.byKey(const Key('reader-finished')), findsOneWidget);
    // Progress is measured to the last paragraph: the footer does not pull
    // the bar back.
    expect(_barFill(tester), greaterThan(0.99));

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
    expect(find.byKey(const Key('reader-finished')), findsOneWidget);
    await _close(tester);
  });

  testWidgets('long-press looks a word up; saving bounces and underlines', (
    tester,
  ) async {
    final vocab = FakeVocabRepository();
    await _open(tester, paragraphs: 3, vocab: vocab, dictionary: _dictionary);
    await _run(tester, const Duration(seconds: 1));

    await tester.longPressAt(_wordCenter(tester, 0, 'reading'));
    await _run(tester, const Duration(milliseconds: 600));
    expect(find.text('v.'), findsOneWidget);
    expect(find.text('读，阅读'), findsOneWidget);
    expect(find.text('原形 read'), findsOneWidget);
    expect(find.text('收藏到生词本'), findsOneWidget);
    // The word stays marked while its sheet is open.
    expect(
      tester
          .widget<ReaderParagraph>(find.byType(ReaderParagraph).first)
          .selected,
      isNotNull,
    );

    await tester.tap(find.byType(CollectButton));
    await tester.pump(); // the bounce starts on this frame
    await tester.pump(const Duration(milliseconds: 120));
    final scale = tester
        .widget<ScaleTransition>(find.byKey(const Key('collect-icon-scale')))
        .scale
        .value;
    expect(scale, isNot(1.0), reason: 'mid-bounce');
    await _run(tester, CollectButton.bounce);
    expect(find.text('已收藏'), findsOneWidget);

    final saved = vocab.items.single;
    expect(saved.lemma, 'read');
    expect(saved.word, 'reading');
    expect(saved.source.paraIndex, 0);
    expect(saved.source.sentence, contains('reading'));

    // Close the sheet: the selection clears, the saved word is underlined.
    await tester.tapAt(const Offset(400, 40));
    await _run(tester, const Duration(milliseconds: 600));
    final first = tester.widget<ReaderParagraph>(
      find.byType(ReaderParagraph).first,
    );
    expect(first.selected, isNull);
    expect(first.collected, contains('reading'));
    await _close(tester);
  });

  testWidgets('a word missing from the dictionary cannot be saved', (
    tester,
  ) async {
    await _open(tester, paragraphs: 3, dictionary: _dictionary);
    await _run(tester, const Duration(seconds: 1));
    await tester.longPressAt(_wordCenter(tester, 0, 'wraps'));
    await _run(tester, const Duration(milliseconds: 600));
    expect(find.text('本地词典里没有这个词'), findsOneWidget);
    expect(find.byType(CollectButton), findsNothing);
    await tester.tapAt(const Offset(400, 40));
    await _run(tester, const Duration(milliseconds: 600));
    await _close(tester);
  });

  testWidgets('opening from the word list scrolls to the word and flashes it', (
    tester,
  ) async {
    const source = WordSource(
      articleId: 'a1',
      paraIndex: 12,
      charStart: 14,
      charEnd: 18,
    );
    await _open(tester, paragraphs: 20, words: 2000, jumpTo: source);
    await _run(tester, const Duration(milliseconds: 1500));

    expect(_scroll(tester).pixels, greaterThan(500));
    final flashing = tester.widget<ReaderParagraph>(
      find.byType(ReaderParagraph).at(12),
    );
    expect(flashing.pulse?.$1, const TextRange(start: 14, end: 18));

    await _run(tester, ReaderPage.pulseDuration);
    expect(
      tester.widget<ReaderParagraph>(find.byType(ReaderParagraph).at(12)).pulse,
      isNull,
    );
    expect(_hintVisible(tester), isFalse);
    await _close(tester);
  });

  testWidgets('the finish card shows the numbers and opens the next article', (
    tester,
  ) async {
    await _open(tester, paragraphs: 1, next: _article(id: 'a2'));
    await _run(tester, const Duration(seconds: 2));

    expect(find.byKey(const Key('finish-card')), findsOneWidget);
    expect(find.text('累计读完'), findsOneWidget);
    await tester.tap(find.text('继续阅读下一篇'));
    await _run(tester, const Duration(seconds: 1));

    expect(find.byType(ReaderPage), findsOneWidget, reason: 'replaced');
    expect(
      tester.widget<ReaderPage>(find.byType(ReaderPage)).surface,
      FinishOverlay.nextSurface,
    );
    expect(find.text('Title of a2'), findsWidgets);
    await _close(tester);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('the bottom bar steps to the next article', (tester) async {
    await _open(tester, paragraphs: 3, next: _article(id: 'a2'));
    await _run(tester, const Duration(seconds: 1));

    await tester.tap(find.byKey(const Key('reader-next')));
    await _run(tester, const Duration(seconds: 1));
    expect(find.text('Title of a2'), findsOneWidget);
    expect(find.byType(ReaderPage), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a bigger font keeps the paragraph at the top in view', (
    tester,
  ) async {
    await _open(tester, paragraphs: 20, words: 2000);
    await _run(tester, const Duration(seconds: 1));
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -2500));
    await tester.pumpAndSettle();

    final paragraphs = find.byType(ReaderParagraph);
    int atTop() {
      for (var i = 0; i < 20; i++) {
        final rect = tester.getRect(paragraphs.at(i));
        if (rect.top <= 0 && rect.bottom > 0) return i;
      }
      return -1;
    }

    final before = atTop();
    expect(before, greaterThan(2));
    ProviderScope.containerOf(
      tester.element(find.byType(ReaderPage)),
    ).read(readerSettingsProvider.notifier).setFontSize(24);
    await tester.pump();
    await tester.pump();
    expect(atTop(), before);
    await _close(tester);
  });
}
