import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/core/widgets/article_cover.dart';

Future<void> _pump(WidgetTester tester, String category) => tester.pumpWidget(
  MaterialApp(
    home: SizedBox.square(
      dimension: 84,
      child: ArticleCover(palette: 'g3', category: category),
    ),
  ),
);

void main() {
  testWidgets('known categories show the designer illustration', (
    tester,
  ) async {
    for (final c in ['tech', 'business', 'culture', 'daily']) {
      await _pump(tester, c);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, 'assets/covers/$c.webp');
      expect(image.fit, BoxFit.cover);
    }
  });

  testWidgets('unknown categories fall back to the gradient', (tester) async {
    await _pump(tester, 'science');
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.article_rounded), findsOneWidget);
  });
}
