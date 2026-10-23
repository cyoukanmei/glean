import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/core/widgets/article_cover.dart';

Future<void> _pump(WidgetTester tester, Size size) => tester.pumpWidget(
  MaterialApp(
    home: Center(
      child: SizedBox.fromSize(
        size: size,
        child: const ArticleCover(
          seed: 'a1',
          title: 'Pride and Prejudice',
          band: 'JANE AUSTEN',
          footer: '拾读 · 名著',
        ),
      ),
    ),
  ),
);

void main() {
  test('the colour is stable per id and varies between ids', () {
    expect(
      ArticleCover.colorFor('tech-1-a'),
      ArticleCover.colorFor('tech-1-a'),
    );
    final colors = {
      for (var i = 0; i < 40; i++) ArticleCover.colorFor('article-$i'),
    };
    expect(colors.length, greaterThan(5));
  });

  testWidgets('tiny covers show the initial only', (tester) async {
    await _pump(tester, const Size(40, 40));
    expect(find.text('P'), findsOneWidget);
    expect(find.text('Pride and Prejudice'), findsNothing);
  });

  testWidgets('list thumbnails show the title but not the band', (
    tester,
  ) async {
    await _pump(tester, const Size(78, 78));
    expect(find.text('Pride and Prejudice'), findsOneWidget);
    expect(find.text('JANE AUSTEN'), findsNothing);
  });

  testWidgets('the wide header stands a book with band and footer', (
    tester,
  ) async {
    await _pump(tester, const Size(412, 340));
    expect(find.text('JANE AUSTEN'), findsOneWidget);
    expect(find.text('拾读 · 名著'), findsOneWidget);
    expect(
      tester.getSize(find.text('Pride and Prejudice')).width,
      lessThan(200),
      reason: 'a portrait book, not the full header width',
    );
  });

  testWidgets('every size along a Hero flight lays out without overflow', (
    tester,
  ) async {
    for (var w = 60.0; w <= 412; w += 22) {
      final h = 60 + (340 - 60) * (w - 60) / (412 - 60);
      await _pump(tester, Size(w, h));
      expect(tester.takeException(), isNull, reason: '$w x $h');
    }
  });

  testWidgets('a long word shrinks the title instead of breaking', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 78,
            child: ArticleCover(seed: 'x', title: 'Unquestionably Wonderland'),
          ),
        ),
      ),
    );
    final text = find.text('Unquestionably Wonderland');
    final size = tester.widget<Text>(text).style!.fontSize!;
    // Shrunk below the size the jacket would otherwise use, but never below
    // the 7 px floor. (The test font's square glyphs are much wider than a
    // real serif, so here the floor is reached.)
    expect(size, lessThan(78 * 0.145));
    expect(size, greaterThanOrEqualTo(7));
  });
}
