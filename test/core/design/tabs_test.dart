import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/core/design/tabs.dart';

void main() {
  testWidgets('the bar slides under the tapped tab', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TextTabs(
              labels: const ['推荐', '名著', '科技', '商业', '文化', '日常'],
              selected: selected,
              onSelected: (i) => setState(() => selected = i),
            ),
          ),
        ),
      ),
    );
    double barCentre() =>
        tester.getCenter(find.byKey(const Key('text-tab-bar'))).dx;

    expect(barCentre(), closeTo(tester.getCenter(find.text('推荐')).dx, 1));
    await tester.tap(find.text('科技'));
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(barCentre(), closeTo(tester.getCenter(find.text('科技')).dx, 1));
  });

  testWidgets('pills show counts and report the picked value', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PillTabs<String>(
            value: 'all',
            items: const {'all': '全部', 'new': '新词'},
            counts: const {'all': 46, 'new': 12},
            onChanged: (v) => picked = v,
          ),
        ),
      ),
    );
    expect(find.text('全部 46', findRichText: true), findsOneWidget);
    await tester.tap(find.byKey(const Key('pill-new')));
    expect(picked, 'new');
  });
}
