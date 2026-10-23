import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../data/auth_repository.dart';

/// The user restored from a saved token at launch (null: show login).
/// Overridden in main after the token has been checked against `sessions`.
final initialUserProvider = Provider<AuthUser?>((ref) => null);

/// Signed-in user; null while signed out.
class AuthNotifier extends Notifier<AuthUser?> {
  static const tokenKey = 'auth.token';

  @override
  AuthUser? build() => ref.watch(initialUserProvider);

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> login(String username, String password) async {
    await _repo.ensureDemoUser();
    final (user, token) = await _repo.login(username, password);
    await ref.read(prefsProvider).setString(tokenKey, token);
    Analytics.track('login', {'user': user.username});
    state = user;
  }

  Future<void> register(String username, String password) async {
    await _repo.register(username, password);
    Analytics.track('register', {'user': username.trim()});
    await login(username, password);
  }

  Future<void> logout() async {
    final prefs = ref.read(prefsProvider);
    if (prefs.getString(tokenKey) case final token?) await _repo.logout(token);
    await prefs.remove(tokenKey);
    Analytics.track('logout');
    state = null;
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthUser?>(
  AuthNotifier.new,
);
