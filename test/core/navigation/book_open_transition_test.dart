import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/core/navigation/book_open_transition.dart';
import 'package:glean/core/navigation/swipe_back_route.dart';

const _origin = Rect.fromLTWH(20, 100, 78, 104);
const _title = 'A Tale of Two Cities';

/// A page with state, to check the transition never rebuilds it.
class _Page extends StatefulWidget {
  const _Page();

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('reader')));
}

double _readerOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .ancestor(of: find.text('reader'), matching: find.byType(Opacity))
          .first,
    )
    .opacity;

void main() {
  testWidgets('opens as a book onto a title page, then the reader; a slow '
      'back swipe closes it under the finger and springs back when let go', (
    tester,
  ) async {
    final lifted = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                SwipeBackPageRoute<void>(
                  builder: (_) => const _Page(),
                  book: BookOpening(
                    origin: _origin,
                    originRadius: 6,
                    cover: (r) => const ColoredBox(
                      key: Key('book-cover'),
                      color: Colors.indigo,
                    ),
                    titlePage: const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [Text(_title), Text('Charles Dickens')],
                      ),
                    ),
                    paper: const Color(0xFFFAF1E2),
                    onLifted: lifted.add,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    final page = tester.state(find.byType(_Page, skipOffstage: false));
    expect(lifted.last, isTrue);

    // In hand: the closed cover, the reader still invisible.
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('book-cover')), findsOneWidget);
    expect(_readerOpacity(tester), 0);

    // Half-way: the cover is open on the title page.
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text(_title), findsOneWidget);
    expect(find.text('Charles Dickens'), findsOneWidget);
    expect(_readerOpacity(tester), 0, reason: 'titles never overlap');

    await tester.pumpAndSettle();
    expect(find.text(_title), findsNothing);
    expect(find.byKey(const Key('book-cover')), findsNothing);
    expect(_readerOpacity(tester), 1);
    expect(tester.state(find.byType(_Page)), same(page), reason: 'not rebuilt');

    // A slow drag right a quarter of the width: back on the open spread,
    // the cover's endpaper on the left, the title page on the right.
    final gesture = await tester.startGesture(const Offset(300, 300));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.text('拾读'), findsOneWidget);
    expect(find.text(_title), findsOneWidget);
    expect(_readerOpacity(tester), 0);

    // Let go short of half-way: it opens again.
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text(_title), findsNothing);
    expect(_readerOpacity(tester), 1);
    expect(tester.state(find.byType(_Page)), same(page));

    // Back for real: the book lands on the list.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(_Page), findsNothing);
    expect(lifted.last, isFalse);
  });
}
