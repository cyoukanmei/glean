import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/app/providers.dart';
import 'package:glean/features/auth/application/auth.dart';
import 'package:glean/features/auth/data/auth_repository.dart';
import 'package:glean/features/profile/data/avatar_store.dart';
import 'package:glean/features/profile/ui/edit_profile_page.dart';
import 'package:glean/features/profile/ui/user_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the profile in memory (no SQLite inside fake async).
class _Repo implements AuthRepository {
  final calls = <Map<String, Object?>>[];

  @override
  Future<AuthUser> updateProfile(
    String userId, {
    required String displayName,
    required String? avatar,
    required String bio,
    required int dailyGoalMinutes,
  }) async {
    if (displayName.trim().isEmpty) throw const AuthException('昵称不能为空');
    calls.add({
      'name': displayName,
      'avatar': avatar,
      'goal': dailyGoalMinutes,
    });
    return AuthUser(
      id: userId,
      username: 'demo',
      displayName: displayName.trim(),
      avatar: avatar,
      bio: bio,
      dailyGoalMinutes: dailyGoalMinutes,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements AvatarStore {
  final discarded = <String?>[];

  @override
  Future<String?> pickFromGallery(String userId) async => null;

  @override
  Future<void> discard(String? avatar) async => discarded.add(avatar);
}

Future<(ProviderContainer, _Repo)> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = _Repo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(repo),
        avatarStoreProvider.overrideWithValue(_Store()),
        initialUserProvider.overrideWithValue(
          const AuthUser(id: 'u1', username: 'demo'),
        ),
      ],
      child: MaterialApp(
        // A Scaffold underneath, where the "saved" snack bar shows.
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EditProfilePage(),
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
  return (
    ProviderScope.containerOf(tester.element(find.byType(EditProfilePage))),
    repo,
  );
}

void main() {
  testWidgets('pick a preset, rename, set a goal and save', (tester) async {
    final (container, repo) = await _pump(tester);

    await tester.tap(find.byKey(const Key('profile-avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择预设头像'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preset-3')));
    await tester.pumpAndSettle();
    expect(find.byType(PresetAvatar), findsOneWidget);

    await tester.enterText(find.byKey(const Key('profile-name')), '小读者');
    await tester.tap(find.text('20 分钟'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();

    expect(repo.calls.single, {
      'name': '小读者',
      'avatar': 'preset:3',
      'goal': 20,
    });
    final user = container.read(authProvider)!;
    expect(user.name, '小读者');
    expect(find.byType(EditProfilePage), findsNothing, reason: 'popped');
    expect(find.text('资料已保存'), findsOneWidget);
  });

  testWidgets('an empty nickname shows the error and stays', (tester) async {
    final (_, repo) = await _pump(tester);
    await tester.enterText(find.byKey(const Key('profile-name')), '  ');
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(find.text('昵称不能为空'), findsOneWidget);
    expect(find.byType(EditProfilePage), findsOneWidget);
    expect(repo.calls, isEmpty);
  });
}
