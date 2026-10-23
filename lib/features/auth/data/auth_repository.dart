import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/clock.dart';

/// A signed-in user and their editable profile.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    this.displayName,
    this.avatar,
    this.bio,
    this.dailyGoalMinutes = 15,
  });

  factory AuthUser.fromRow(Map<String, Object?> row) => AuthUser(
    id: row['id']! as String,
    username: row['username']! as String,
    displayName: row['display_name'] as String?,
    avatar: row['avatar'] as String?,
    bio: row['bio'] as String?,
    dailyGoalMinutes: row['daily_goal_min'] as int? ?? 15,
  );

  final String id;
  final String username;

  /// Shown instead of [username] when set.
  final String? displayName;

  /// `preset:<n>` or `file:<path>`; null shows the initial.
  final String? avatar;
  final String? bio;
  final int dailyGoalMinutes;

  String get name =>
      (displayName?.trim().isNotEmpty ?? false) ? displayName! : username;
}

/// Why a login or sign-up was refused; shown under the form.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Local accounts and sessions (mock backend).
///
/// Passwords are stored as `sha256(salt + password)` with a random salt per
/// user. A login creates a random token in `sessions` that expires after
/// [sessionTtl]; the token is the only thing kept on the client. A real
/// backend would do the hashing and issue the token server-side.
class AuthRepository {
  AuthRepository(
    this._db, {
    this._clock = systemClock,
    Uuid? uuid,
    Random? random,
  }) : _uuid = uuid ?? const Uuid(),
       _random = random ?? Random.secure();

  final DatabaseExecutor _db;
  final Clock _clock;
  final Uuid _uuid;
  final Random _random;

  static const sessionTtl = Duration(days: 7);
  static const demoUsername = 'demo';
  static const demoPassword = 'glean123';

  /// Data read before anyone signed in is kept under this id and handed to
  /// the first account that logs in on the device.
  static const guestId = 'guest';

  static const _userTables = [
    'reading_progress',
    'reading_segments',
    'vocab',
    'article_marks',
  ];

  static final _usernamePattern = RegExp(r'^[A-Za-z0-9_]{3,20}$');

  String _hash(String salt, String password) =>
      sha256.convert(utf8.encode('$salt$password')).toString();

  String _salt() => [
    for (var i = 0; i < 16; i++) _random.nextInt(256),
  ].map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Creates the demo account if it is missing.
  Future<void> ensureDemoUser() async {
    final rows = await _db.query(
      'users',
      columns: ['id'],
      where: 'username = ?',
      whereArgs: [demoUsername],
    );
    if (rows.isEmpty) await register(demoUsername, demoPassword);
  }

  Future<AuthUser> register(String username, String password) async {
    final name = username.trim();
    if (!_usernamePattern.hasMatch(name)) {
      throw const AuthException('账号需为 3–20 位字母、数字或下划线');
    }
    if (password.length < 6) throw const AuthException('密码至少 6 位');
    final salt = _salt();
    final id = _uuid.v4();
    try {
      await _db.insert('users', {
        'id': id,
        'username': name,
        'password_hash': _hash(salt, password),
        'salt': salt,
        'created_at': _clock(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw const AuthException('这个账号已经被注册了');
      }
      rethrow;
    }
    return AuthUser(id: id, username: name);
  }

  static const maxNameLength = 16;
  static const maxBioLength = 40;

  /// Saves the editable profile fields and returns the updated user.
  Future<AuthUser> updateProfile(
    String userId, {
    required String displayName,
    required String? avatar,
    required String bio,
    required int dailyGoalMinutes,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) throw const AuthException('昵称不能为空');
    if (name.runes.length > maxNameLength) {
      throw const AuthException('昵称最多 $maxNameLength 个字');
    }
    if (bio.trim().runes.length > maxBioLength) {
      throw const AuthException('签名最多 $maxBioLength 个字');
    }
    if (dailyGoalMinutes < 5 || dailyGoalMinutes > 120) {
      throw const AuthException('每日目标需在 5–120 分钟之间');
    }
    await _db.update(
      'users',
      {
        'display_name': name,
        'avatar': avatar,
        'bio': bio.trim(),
        'daily_goal_min': dailyGoalMinutes,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    final rows = await _db.query('users', where: 'id = ?', whereArgs: [userId]);
    return AuthUser.fromRow(rows.single);
  }

  /// Checks the password and opens a session. Returns the new token.
  Future<(AuthUser, String token)> login(
    String username,
    String password,
  ) async {
    final rows = await _db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username.trim()],
    );
    if (rows.isEmpty) throw const AuthException('账号或密码不正确');
    final row = rows.single;
    if (_hash(row['salt']! as String, password) != row['password_hash']) {
      throw const AuthException('账号或密码不正确');
    }
    final user = AuthUser.fromRow(row);
    final now = _clock();
    final token = _uuid.v4();
    await _db.insert('sessions', {
      'token': token,
      'user_id': user.id,
      'created_at': now,
      'expires_at': now + sessionTtl.inMilliseconds,
    });
    await _adoptGuestData(user.id);
    return (user, token);
  }

  /// The user a stored token belongs to, or null when it is unknown or has
  /// expired (expired sessions are removed).
  Future<AuthUser?> userForToken(String token) async {
    final rows = await _db.rawQuery(
      '''
      SELECT u.*, s.expires_at
      FROM sessions s JOIN users u ON u.id = s.user_id
      WHERE s.token = ?''',
      [token],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    if ((row['expires_at']! as int) <= _clock()) {
      await logout(token);
      return null;
    }
    return AuthUser.fromRow(row);
  }

  Future<void> logout(String token) =>
      _db.delete('sessions', where: 'token = ?', whereArgs: [token]);

  /// Progress and words saved before signing in move to the account (rows
  /// the account already has win).
  Future<void> _adoptGuestData(String userId) async {
    for (final table in _userTables) {
      await _db.rawUpdate(
        'UPDATE OR IGNORE $table SET user_id = ? WHERE user_id = ?',
        [userId, guestId],
      );
    }
  }
}
