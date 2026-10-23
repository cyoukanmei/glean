import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/app/providers.dart';
import 'package:glean/features/auth/application/auth.dart';
import 'package:glean/features/auth/data/auth_repository.dart';
import 'package:glean/features/auth/ui/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Accepts only the demo account (no SQLite inside fake async).
class _Repo implements AuthRepository {
  @override
  Future<void> ensureDemoUser() async {}

  @override
  Future<(AuthUser, String)> login(String username, String password) async {
    if (username != 'demo' || password != 'glean123') {
      throw const AuthException('账号或密码不正确');
    }
    return (const AuthUser(id: 'u1', username: 'demo'), 'token-1');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('a wrong password shakes and shows the error; demo signs in', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          authRepositoryProvider.overrideWithValue(_Repo()),
        ],
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LoginPage)),
    );

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('login-username')),
        matching: find.byType(TextField),
      ),
      'demo',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('login-password')),
        matching: find.byType(TextField),
      ),
      'wrong',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('账号或密码不正确'), findsOneWidget);
    expect(container.read(authProvider), isNull);
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('演示账号'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(container.read(authProvider)?.username, 'demo');
    expect(prefs.getString(AuthNotifier.tokenKey), 'token-1');
    expect(container.read(currentUserIdProvider), 'u1');
  });
}
