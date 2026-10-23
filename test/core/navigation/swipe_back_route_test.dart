import 'package:english_reader/core/navigation/swipe_back_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _pageA = Key('page-a');
const _pageB = Key('page-b');
const _list = Key('list-b');

/// Test surface is 800 x 600; page B is a long scrollable list.
Future<void> _pumpAndOpenB(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: (settings) => SwipeBackPageRoute<void>(
        settings: settings,
        builder: (context) => Scaffold(
          key: _pageA,
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                SwipeBackPageRoute<void>(
                  builder: (_) => Scaffold(
                    key: _pageB,
                    body: ListView.builder(
                      key: _list,
                      itemCount: 100,
                      itemBuilder: (_, i) =>
                          SizedBox(height: 60, child: Text('row $i')),
                    ),
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
  await tester.pumpAndSettle();
  expect(find.byKey(_pageB), findsOneWidget);
}

double _pageBLeft(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(_pageB)).dx;

NavigatorState _navigator(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator));

/// Drags slowly (no fling) in small steps from the page centre.
Future<TestGesture> _slowDrag(WidgetTester tester, Offset by) async {
  final gesture = await tester.startGesture(const Offset(400, 300));
  const steps = 20;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(by / steps.toDouble());
    await tester.pump(const Duration(milliseconds: 50));
  }
  return gesture;
}

Future<void> _sendBack(
  WidgetTester tester,
  String method, [
  double progress = 0,
]) async {
  final args = <String, Object?>{
    'touchOffset': <double>[0, 300],
    'progress': progress,
    'swipeEdge': 0,
  };
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.backGesture.name,
    SystemChannels.backGesture.codec.encodeMethodCall(
      MethodCall(
        method,
        method.startsWith(RegExp('start|update')) ? args : null,
      ),
    ),
    (_) {},
  );
  await tester.pump();
}

void main() {
  group('in-app swipe back', () {
    testWidgets('page follows the finger 1:1 while dragging', (tester) async {
      await _pumpAndOpenB(tester);
      final gesture = await _slowDrag(tester, const Offset(200, 0));

      // Movement counts from touch-down, so the slop is not lost.
      expect(_pageBLeft(tester), moreOrLessEquals(200, epsilon: 0.5));
      expect(_navigator(tester).userGestureInProgress, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('releasing before halfway springs back', (tester) async {
      await _pumpAndOpenB(tester);
      final gesture = await _slowDrag(tester, const Offset(280, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byKey(_pageB), findsOneWidget);
      expect(_pageBLeft(tester), 0);
      expect(_navigator(tester).userGestureInProgress, isFalse);
    });

    testWidgets('releasing past halfway pops', (tester) async {
      await _pumpAndOpenB(tester);
      final gesture = await _slowDrag(tester, const Offset(480, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byKey(_pageB), findsNothing);
      expect(find.byKey(_pageA), findsOneWidget);
      expect(_navigator(tester).userGestureInProgress, isFalse);
    });

    testWidgets('a quick short fling pops', (tester) async {
      await _pumpAndOpenB(tester);
      await tester.flingFrom(
        const Offset(400, 300),
        const Offset(120, 0),
        2000,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_pageB), findsNothing);
    });

    testWidgets('a diagonal flick scrolls instead of going back', (
      tester,
    ) async {
      await _pumpAndOpenB(tester);
      final gesture = await tester.startGesture(const Offset(400, 300));
      // 20 px right, 15 px up: a plain horizontal recognizer would win this.
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(4, -3));
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Keep scrolling up; the scroll view applies moves after it has won.
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(_pageBLeft(tester), 0);
      expect(_navigator(tester).userGestureInProgress, isFalse);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(_list),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.pixels, greaterThan(100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(_pageB), findsOneWidget);
    });

    testWidgets('a leftward drag does nothing', (tester) async {
      await _pumpAndOpenB(tester);
      final gesture = await _slowDrag(tester, const Offset(-200, 0));
      expect(_pageBLeft(tester), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(_pageB), findsOneWidget);
    });

    testWidgets('no gesture on the first route', (tester) async {
      await _pumpAndOpenB(tester);
      _navigator(tester).pop();
      await tester.pumpAndSettle();

      final gesture = await _slowDrag(tester, const Offset(300, 0));
      expect(tester.getTopLeft(find.byKey(_pageA)).dx, 0);
      expect(_navigator(tester).userGestureInProgress, isFalse);
      await gesture.up();
    });
  });

  group('system predictive back', () {
    testWidgets('progress drives the same animation; commit pops', (
      tester,
    ) async {
      await _pumpAndOpenB(tester);

      await _sendBack(tester, 'startBackGesture', 0);
      await _sendBack(tester, 'updateBackGestureProgress', 0.4);
      expect(_pageBLeft(tester), moreOrLessEquals(320, epsilon: 1));
      expect(_navigator(tester).userGestureInProgress, isTrue);

      await _sendBack(tester, 'commitBackGesture');
      // Settles from where the finger left it, no jump back to fully shown.
      expect(_pageBLeft(tester), greaterThan(319.9));
      await tester.pumpAndSettle();

      expect(find.byKey(_pageB), findsNothing);
      expect(_navigator(tester).userGestureInProgress, isFalse);
    });

    testWidgets('cancel springs back', (tester) async {
      await _pumpAndOpenB(tester);

      await _sendBack(tester, 'startBackGesture', 0);
      await _sendBack(tester, 'updateBackGestureProgress', 0.3);
      await _sendBack(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();

      expect(find.byKey(_pageB), findsOneWidget);
      expect(_pageBLeft(tester), 0);
      expect(_navigator(tester).userGestureInProgress, isFalse);
    });
  });
}
