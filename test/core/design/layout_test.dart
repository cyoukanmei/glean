import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/core/design/layout.dart';

void main() {
  testWidgets('centres the child at its max width; the wheel works in the '
      'margins too', (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CenteredColumn(
          maxWidth: 700,
          child: ListView(
            key: const Key('list'),
            controller: scroll,
            children: [for (var i = 0; i < 50; i++) SizedBox(height: 60)],
          ),
        ),
      ),
    );
    final list = tester.getRect(find.byKey(const Key('list')));
    expect(list.width, 700);
    expect(list.center.dx, 700);

    // Wheel over the left margin, outside the list.
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(100, 400)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 240)));
    await tester.pumpAndSettle();
    expect(scroll.offset, 240);
  });

  testWidgets('a narrow window gets the child at full width', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: CenteredColumn(
          maxWidth: 700,
          child: SizedBox.expand(key: Key('child')),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const Key('child'))).width, 390);
    expect(
      Layout.isWide(tester.element(find.byKey(const Key('child')))),
      isFalse,
    );
  });
}
