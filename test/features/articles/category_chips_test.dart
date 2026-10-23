import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/features/articles/ui/category_chips.dart';

void main() {
  testWidgets('six tabs fit a 360 pt wide phone without scrolling', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoryChips(
            labels: const ['推荐', '名著', '科技', '商业', '文化', '日常'],
            selected: 5,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('日常')).right, lessThanOrEqualTo(360 - 16));
    // The pill sits under the selected (last) tab.
    final pill = tester.getRect(find.byKey(const Key('chip-indicator')));
    expect(pill.right, lessThanOrEqualTo(360 - 16 + 0.5));
  });
}
