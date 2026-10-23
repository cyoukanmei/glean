import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/analytics/analytics.dart';
import '../../core/clock.dart';
import '../auth/data/auth_repository.dart';
import 'data/mock_sync_server.dart';
import 'data/sync_merge.dart';

class SyncResult {
  const SyncResult({
    required this.at,
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = const [],
    this.skipped,
    this.error,
  });

  final int at;
  final int pushed;
  final int pulled;

  /// One line per record that someone else had changed in the meantime.
  final List<String> conflicts;

  /// Why nothing ran (guest, offline).
  final String? skipped;
  final String? error;

  bool get ok => skipped == null && error == null;
}

/// Two-way sync of reading progress and the word list.
///
/// Local writes set `dirty = 1` (see the repositories). A sync pushes dirty
/// rows with the server version they were based on, applies what the server
/// answers (its merged record), then pulls what other devices changed since
/// the last cursor. Both sides use [SyncMerge], so they converge.
///
/// Runs on start, every [interval], a few seconds after local changes, when
/// the app comes back to the foreground and when the network returns. Only
/// signed-in accounts sync; guest data stays local.
class SyncService extends ChangeNotifier {
  SyncService({
    required this.db,
    required this.server,
    required this.deviceId,
    required this.userId,
    required this.isOnline,
    required this.onRemoteChanges,
    this._clock = systemClock,
    this.interval = const Duration(minutes: 1),
    this.debounce = const Duration(seconds: 3),
  });

  final Database db;
  final MockSyncServer server;
  final String deviceId;
  final String Function() userId;
  final bool Function() isOnline;

  /// Pulled changes landed locally: pages should reload.
  final VoidCallback onRemoteChanges;
  final Clock _clock;
  final Duration interval;
  final Duration debounce;

  SyncResult? last;
  int? lastOkAt;

  /// Recent conflicts, newest first (for the sync page).
  final conflictLog = <(int at, String text)>[];

  Future<SyncResult>? _running;
  Timer? _timer;
  Timer? _soon;
  AppLifecycleListener? _lifecycle;

  bool get running => _running != null;

  void start() {
    _timer = Timer.periodic(interval, (_) => sync());
    _lifecycle = AppLifecycleListener(onResume: sync);
    _soon = Timer(debounce, sync);
  }

  /// A local change happened: sync shortly, coalescing bursts of writes.
  void scheduleSoon() {
    _soon?.cancel();
    _soon = Timer(debounce, sync);
  }

  void onConnectivityChanged(bool online) {
    if (online) sync();
  }

  /// Dirty rows waiting to go up: (progress, words).
  Future<(int, int)> pending() async {
    final user = userId();
    Future<int> count(String table) async =>
        (await db.rawQuery(
              'SELECT COUNT(*) AS n FROM $table WHERE user_id = ? AND dirty = 1',
              [user],
            )).single['n']!
            as int;
    return (
      await count('reading_progress'),
      await count('vocab') + await count('article_marks'),
    );
  }

  Future<SyncResult> sync() {
    final running = _running ??= _sync().whenComplete(() {
      _running = null;
      notifyListeners();
    });
    notifyListeners();
    return running;
  }

  Future<SyncResult> _sync() async {
    final now = _clock();
    final user = userId();
    SyncResult result;
    if (user == AuthRepository.guestId) {
      result = SyncResult(at: now, skipped: 'guest');
    } else if (!isOnline()) {
      result = SyncResult(at: now, skipped: 'offline');
    } else {
      try {
        result = await _run(user);
        lastOkAt = _clock();
      } catch (e) {
        debugPrint('[sync] failed: $e');
        result = SyncResult(at: now, error: '$e');
      }
    }
    last = result;
    if (result.skipped == null) {
      Analytics.track('sync_run', {
        'pushed': result.pushed,
        'pulled': result.pulled,
        'conflicts': result.conflicts.length,
        'ok': result.ok,
      });
    }
    return result;
  }

  Future<SyncResult> _run(String user) async {
    final conflicts = <String>[];

    // Push.
    final progressRows = await db.query(
      'reading_progress',
      where: 'user_id = ? AND dirty = 1',
      whereArgs: [user],
    );
    final vocabRows = await db.query(
      'vocab',
      where: 'user_id = ? AND dirty = 1',
      whereArgs: [user],
    );
    final markRows = await db.query(
      'article_marks',
      where: 'user_id = ? AND dirty = 1',
      whereArgs: [user],
    );
    final changes = [
      for (final r in progressRows)
        SyncChange(
          kind: 'progress',
          key: r['article_id']! as String,
          payload: _progressPayload(r),
          baseVersion: r['version']! as int,
        ),
      for (final r in vocabRows)
        SyncChange(
          kind: 'vocab',
          key: r['lemma']! as String,
          payload: _vocabPayload(r),
          baseVersion: r['version']! as int,
        ),
      for (final r in markRows)
        SyncChange(
          kind: 'mark',
          key: '${r['kind']}:${r['article_id']}',
          payload: _markPayload(r),
          baseVersion: r['version']! as int,
        ),
    ];
    if (changes.isNotEmpty) {
      final response =
          jsonDecode(
                await server.push(
                  jsonEncode({
                    'user_id': user,
                    'device_id': deviceId,
                    'changes': [for (final c in changes) c.toJson()],
                  }),
                ),
              )
              as Map<String, dynamic>;
      final results = (response['results'] as List)
          .cast<Map<String, dynamic>>()
          .map(SyncChange.fromJson)
          .toList();
      await db.transaction((txn) async {
        for (final r in results) {
          await _applyLocal(txn, user, r);
          if (r.conflict) conflicts.add(_describe(r));
        }
      });
    }

    // Pull.
    final cursorKey = 'sync.cursor.$user';
    final meta = await db.query(
      'app_meta',
      where: 'key = ?',
      whereArgs: [cursorKey],
    );
    final since = meta.isEmpty ? 0 : int.parse(meta.single['value']! as String);
    final pulled =
        jsonDecode(await server.pull(user, deviceId, since))
            as Map<String, dynamic>;
    final remote = (pulled['changes'] as List)
        .cast<Map<String, dynamic>>()
        .map(SyncChange.fromJson)
        .toList();
    var applied = 0;
    await db.transaction((txn) async {
      for (final r in remote) {
        if (await _applyLocal(txn, user, r)) applied++;
      }
      await txn.insert('app_meta', {
        'key': cursorKey,
        'value': '${pulled['cursor']}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    final now = _clock();
    for (final c in conflicts) {
      conflictLog.insert(0, (now, c));
    }
    if (conflictLog.length > 20) {
      conflictLog.removeRange(20, conflictLog.length);
    }
    if (applied > 0) onRemoteChanges();
    return SyncResult(
      at: now,
      pushed: changes.length,
      pulled: applied,
      conflicts: conflicts,
    );
  }

  static String _describe(SyncChange c) => switch (c.kind) {
    'progress' => '《${c.key}》的阅读进度在别的设备上也变了，已合并（进度取最大，位置取最近一次阅读）',
    'mark' => '《${c.payload['article_id']}》的收藏 / 稍后再读两边都改过，保留了较新的一次',
    _ => '生词「${c.payload['word'] ?? c.key}」两边都改过，按最后修改时间保留了较新的一份',
  };

  static Map<String, Object?> _progressPayload(Map<String, Object?> r) => {
    for (final f in SyncMerge.positionFields) f: r[f],
    'max_progress': r['max_progress'],
    'status': r['status'],
    'finished_at': r['finished_at'],
    'last_read_at': r['last_read_at'],
    'updated_at': r['updated_at'],
  };

  static const _vocabFields = [
    'id',
    'word',
    'lemma',
    'definition',
    'article_id',
    'para_index',
    'char_start',
    'char_end',
    'sentence',
    'created_at',
    'updated_at',
    'deleted_at',
    'status',
  ];

  static Map<String, Object?> _vocabPayload(Map<String, Object?> r) => {
    for (final f in _vocabFields) f: r[f],
  };

  static const _markFields = [
    'article_id',
    'kind',
    'created_at',
    'updated_at',
    'deleted_at',
  ];

  static Map<String, Object?> _markPayload(Map<String, Object?> r) => {
    for (final f in _markFields) f: r[f],
  };

  /// Applies a server record locally. Returns whether anything changed.
  Future<bool> _applyLocal(Transaction txn, String user, SyncChange c) =>
      switch (c.kind) {
        'progress' => _applyProgress(txn, user, c),
        'mark' => _applyMark(txn, user, c),
        _ => _applyVocab(txn, user, c),
      };

  Future<bool> _applyMark(Transaction txn, String user, SyncChange c) async {
    final where = 'user_id = ? AND article_id = ? AND kind = ?';
    final args = [user, c.payload['article_id'], c.payload['kind']];
    final rows = await txn.query(
      'article_marks',
      where: where,
      whereArgs: args,
    );
    if (rows.isEmpty) {
      await txn.insert('article_marks', {
        'user_id': user,
        ...c.payload,
        'version': c.version,
        'dirty': 0,
      });
      return true;
    }
    final local = _markPayload(rows.single);
    if (SyncMerge.vocabWins(local, c.payload)) {
      await txn.update(
        'article_marks',
        {...c.payload, 'version': c.version, 'dirty': 0},
        where: where,
        whereArgs: args,
      );
      return !SyncMerge.same(local, c.payload);
    }
    await txn.update(
      'article_marks',
      {'version': c.version},
      where: where,
      whereArgs: args,
    );
    return false;
  }

  Future<bool> _applyProgress(
    Transaction txn,
    String user,
    SyncChange c,
  ) async {
    final rows = await txn.query(
      'reading_progress',
      where: 'user_id = ? AND article_id = ?',
      whereArgs: [user, c.key],
    );
    if (rows.isEmpty) {
      // Progress for an article this device does not have yet is skipped;
      // it arrives with the next full pull after the article does.
      final article = await txn.query(
        'articles',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [c.key],
      );
      if (article.isEmpty) return false;
      await txn.insert('reading_progress', {
        'user_id': user,
        'article_id': c.key,
        ...c.payload,
        'version': c.version,
        'dirty': 0,
      });
      return true;
    }
    final local = _progressPayload(rows.single);
    final merged = SyncMerge.progress(local, c.payload);
    await txn.update(
      'reading_progress',
      {
        ...merged,
        'version': c.version,
        // Still dirty only if this device has something the server lacks.
        'dirty': SyncMerge.same(merged, c.payload) ? 0 : 1,
      },
      where: 'user_id = ? AND article_id = ?',
      whereArgs: [user, c.key],
    );
    return !SyncMerge.same(merged, local);
  }

  Future<bool> _applyVocab(Transaction txn, String user, SyncChange c) async {
    final rows = await txn.query(
      'vocab',
      where: 'user_id = ? AND lemma = ?',
      whereArgs: [user, c.key],
    );
    final fields = {
      for (final f in _vocabFields)
        if (f != 'id') f: c.payload[f],
    };
    if (rows.isEmpty) {
      await txn.insert('vocab', {
        'id': c.payload['id'],
        'user_id': user,
        ...fields,
        'version': c.version,
        'dirty': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return true;
    }
    final local = _vocabPayload(rows.single);
    if (SyncMerge.vocabWins(local, c.payload)) {
      await txn.update(
        'vocab',
        {...fields, 'version': c.version, 'dirty': 0},
        where: 'user_id = ? AND lemma = ?',
        whereArgs: [user, c.key],
      );
      return !SyncMerge.same({...local}..remove('id'), fields);
    }
    // Edited here after the push: keep it, rebase on the server version.
    await txn.update(
      'vocab',
      {'version': c.version},
      where: 'user_id = ? AND lemma = ?',
      whereArgs: [user, c.key],
    );
    return false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _soon?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}
