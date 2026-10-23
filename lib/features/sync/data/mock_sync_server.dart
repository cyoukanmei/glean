import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/clock.dart';
import 'sync_merge.dart';

/// One record on the wire: `kind` is `progress` (key = article id) or
/// `vocab` (key = lemma).
class SyncChange {
  const SyncChange({
    required this.kind,
    required this.key,
    required this.payload,
    this.version = 0,
    this.baseVersion = 0,
    this.conflict = false,
    this.deviceId,
  });

  factory SyncChange.fromJson(Map<String, dynamic> j) => SyncChange(
    kind: j['kind'] as String,
    key: j['key'] as String,
    payload: (j['payload'] as Map).cast<String, Object?>(),
    version: j['version'] as int? ?? 0,
    baseVersion: j['base_version'] as int? ?? 0,
    conflict: j['conflict'] as bool? ?? false,
    deviceId: j['device_id'] as String?,
  );

  final String kind;
  final String key;
  final Map<String, Object?> payload;

  /// Server version after the change (responses).
  final int version;

  /// The server version the client last saw (requests); a mismatch means
  /// someone else changed the record in between.
  final int baseVersion;
  final bool conflict;
  final String? deviceId;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'key': key,
    'payload': payload,
    'version': version,
    'base_version': baseVersion,
    'conflict': conflict,
    'device_id': ?deviceId,
  };
}

class OfflineSyncException implements Exception {
  const OfflineSyncException();

  @override
  String toString() => 'offline';
}

/// Stand-in for the sync backend (`POST /v1/sync/push`, `GET /v1/sync/pull`),
/// backed by its own SQLite file so it survives restarts like a server
/// would. Requests and responses go through JSON to keep the boundary real.
class MockSyncServer {
  MockSyncServer(
    this._db, {
    required this.isOnline,
    this._clock = systemClock,
    this.latency = const Duration(milliseconds: 300),
  });

  final Database _db;
  final Clock _clock;
  final bool Function() isOnline;
  final Duration latency;

  static const schema = [
    '''
    CREATE TABLE IF NOT EXISTS server_rows (
      kind TEXT NOT NULL,
      user_id TEXT NOT NULL,
      key TEXT NOT NULL,
      payload TEXT NOT NULL,
      version INTEGER NOT NULL,
      device_id TEXT NOT NULL,
      seq INTEGER NOT NULL,
      PRIMARY KEY (kind, user_id, key)
    )''',
    'CREATE INDEX IF NOT EXISTS idx_server_pull ON server_rows(user_id, seq)',
    '''
    CREATE TABLE IF NOT EXISTS server_meta (
      k TEXT PRIMARY KEY,
      v INTEGER NOT NULL
    )''',
  ];

  static Future<Database> open(DatabaseFactory factory, String path) =>
      factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            for (final sql in schema) {
              await db.execute(sql);
            }
          },
        ),
      );

  Future<void> _network() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (!isOnline()) throw const OfflineSyncException();
  }

  /// Applies the client's changes; every change comes back as the server's
  /// resulting record (merged or kept), flagged when it conflicted.
  Future<String> push(String requestJson) async {
    await _network();
    final req = jsonDecode(requestJson) as Map<String, dynamic>;
    final userId = req['user_id'] as String;
    final deviceId = req['device_id'] as String;
    final changes = (req['changes'] as List).cast<Map<String, dynamic>>().map(
      SyncChange.fromJson,
    );
    final results = <SyncChange>[];
    await _db.transaction((txn) async {
      for (final c in changes) {
        results.add(await _apply(txn, userId, deviceId, c));
      }
    });
    return jsonEncode({
      'results': [for (final r in results) r.toJson()],
    });
  }

  Future<SyncChange> _apply(
    Transaction txn,
    String userId,
    String deviceId,
    SyncChange c,
  ) async {
    final rows = await txn.query(
      'server_rows',
      where: 'kind = ? AND user_id = ? AND key = ?',
      whereArgs: [c.kind, userId, c.key],
    );
    final existing = rows.isEmpty ? null : rows.single;
    final current = existing == null
        ? null
        : (jsonDecode(existing['payload']! as String) as Map)
              .cast<String, Object?>();
    final currentVersion = existing?['version'] as int? ?? 0;
    final conflict = existing != null && c.baseVersion != currentVersion;

    final Map<String, Object?> result;
    if (current == null) {
      result = c.payload;
    } else if (c.kind == 'progress') {
      result = SyncMerge.progress(current, c.payload);
    } else {
      result = SyncMerge.vocabWins(current, c.payload) ? c.payload : current;
    }
    if (current != null && SyncMerge.same(current, result)) {
      return SyncChange(
        kind: c.kind,
        key: c.key,
        payload: current,
        version: currentVersion,
        conflict: conflict,
      );
    }
    final version = currentVersion + 1;
    await txn.insert('server_rows', {
      'kind': c.kind,
      'user_id': userId,
      'key': c.key,
      'payload': jsonEncode(result),
      'version': version,
      'device_id': deviceId,
      'seq': await _nextSeq(txn),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return SyncChange(
      kind: c.kind,
      key: c.key,
      payload: result,
      version: version,
      conflict: conflict,
    );
  }

  Future<int> _nextSeq(DatabaseExecutor db) async {
    final rows = await db.query(
      'server_meta',
      where: 'k = ?',
      whereArgs: ['seq'],
    );
    final next = (rows.isEmpty ? 0 : rows.single['v']! as int) + 1;
    await db.insert('server_meta', {
      'k': 'seq',
      'v': next,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return next;
  }

  /// Records other devices changed after [since], and the new cursor.
  Future<String> pull(String userId, String deviceId, int since) async {
    await _network();
    final rows = await _db.query(
      'server_rows',
      where: 'user_id = ? AND seq > ? AND device_id != ?',
      whereArgs: [userId, since, deviceId],
      orderBy: 'seq',
    );
    final cursorRows = await _db.rawQuery(
      'SELECT MAX(seq) AS s FROM server_rows WHERE user_id = ?',
      [userId],
    );
    return jsonEncode({
      'changes': [
        for (final r in rows)
          SyncChange(
            kind: r['kind']! as String,
            key: r['key']! as String,
            payload: (jsonDecode(r['payload']! as String) as Map)
                .cast<String, Object?>(),
            version: r['version']! as int,
            deviceId: r['device_id']! as String,
          ).toJson(),
      ],
      'cursor': cursorRows.single['s'] as int? ?? since,
    });
  }

  /// Demo: another device (a "tablet") marks one saved word as mastered and
  /// reads further in one article. Returns what it changed.
  Future<List<String>> simulateOtherDevice(String userId) async {
    final now = _clock();
    final done = <String>[];
    await _db.transaction((txn) async {
      for (final kind in ['vocab', 'progress']) {
        final rows = await txn.query(
          'server_rows',
          where: 'kind = ? AND user_id = ?',
          whereArgs: [kind, userId],
          orderBy: 'seq DESC',
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final row = rows.single;
        final payload = (jsonDecode(row['payload']! as String) as Map)
            .cast<String, Object?>();
        if (kind == 'vocab') {
          payload['status'] = 2;
          payload['updated_at'] = now;
          done.add('平板把「${payload['word']}」标为已掌握');
        } else {
          final p = ((payload['progress']! as num) + 0.2).clamp(0.0, 1.0);
          payload
            ..['progress'] = p
            ..['max_progress'] = (payload['max_progress']! as num) > p
                ? payload['max_progress']
                : p
            ..['scroll_offset'] = (payload['scroll_offset']! as num) + 600
            ..['last_read_at'] = now
            ..['updated_at'] = now;
          done.add('平板在《${row['key']}》多读了一段');
        }
        await txn.update(
          'server_rows',
          {
            'payload': jsonEncode(payload),
            'version': (row['version']! as int) + 1,
            'device_id': 'tablet',
            'seq': await _nextSeq(txn),
          },
          where: 'kind = ? AND user_id = ? AND key = ?',
          whereArgs: [kind, userId, row['key']],
        );
      }
    });
    return done;
  }
}
