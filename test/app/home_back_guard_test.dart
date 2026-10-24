import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/app/home_back_guard.dart';
import 'package:glean/app/home_tab.dart';

void main() {
  testWidgets('back goes to 书架 first, then needs a second swipe to leave', (
    tester,
  ) async {
    var exits = 0;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(homeTabProvider.notifier).go(HomeTab.vocab);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: HomeBackGuard(
            exit: () async => exits++,
            child: const Scaffold(body: Text('home')),
          ),
        ),
      ),
    );

    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await tester.pump();
    }

    await back();
    expect(container.read(homeTabProvider), HomeTab.shelf);
    expect(find.text('再滑一次退出拾读'), findsNothing);

    await back();
    expect(find.text('再滑一次退出拾读'), findsOneWidget);
    expect(exits, 0);

    await back();
    expect(exits, 1);

    // Too slow: the second swipe only arms it again.
    await tester.pump(const Duration(seconds: 3));
    await back();
    await tester.pump(const Duration(seconds: 3));
    await back();
    expect(exits, 1);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}
