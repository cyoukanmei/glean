import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/app/app_root.dart';
import 'package:glean/app/providers.dart';
import 'package:glean/features/auth/ui/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('splash plays, then a signed-out user lands on login', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          seedReadyProvider.overrideWithValue(Future<void>.value()),
        ],
        child: const MaterialApp(home: AppRoot()),
      ),
    );

    expect(find.byType(SplashPage), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('拾读'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing, reason: 'minimum splash');

    await tester.pump(SplashPage.minDuration);
    await tester.pumpAndSettle();
    expect(find.byType(SplashPage), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
  });
}
