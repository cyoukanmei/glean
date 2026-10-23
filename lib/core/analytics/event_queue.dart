import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../clock.dart';

abstract final class EventStatus {
  static const pending = 0;
  static const sending = 1;
  static const sent = 2;

  /// Gave up after [EventQueue.maxAttempts]; kept for the debug panel.
  static const dead = 3;
}

/// One queued event as stored in `event_queue`.
class QueuedEvent {
  const QueuedEvent({
    required this.eventId,
    required this.name,
    required this.ts,
    required this.sessionId,
    required this.seq,
    required this.userId,
    required this.params,
    this.status = EventStatus.pending,
    this.attempts = 0,
  });

  factory QueuedEvent.fromRow(Map<String, Object?> r) => QueuedEvent(
    eventId: r['event_id']! as String,
    name: r['name']! as String,
    ts: r['ts']! as int,
    sessionId: r['session_id']! as String,
    seq: r['seq']! as int,
    userId: r['user_id'] as String?,
    params: (jsonDecode(r['params']! as String) as Map).cast<String, Object?>(),
    status: r['status']! as int,
    attempts: r['attempts']! as int,
  );

  final String eventId;
  final String name;
  final int ts;
  final String sessionId;
  final int seq;
  final String? userId;

  /// Business and common parameters together, exactly as uploaded.
  final Map<String, Object?> params;
  final int status;
  final int attempts;

  Map<String, Object?> toJson() => {
    'event_id': eventId,
    'name': name,
    'ts': ts,
    'session_id': sessionId,
    'seq': seq,
    'user_id': userId,
    'params': params,
  };
}

/// One upload attempt, for the debug panel.
class UploadRecord {
  const UploadRecord({
    required this.batchId,
    required this.sentAt,
    required this.count,
    required this.httpStatus,
    required this.error,
    required this.durationMs,
  });

  factory UploadRecord.fromRow(Map<String, Object?> r) => UploadRecord(
    batchId: r['batch_id']! as String,
    sentAt: r['sent_at']! as int,
    count: r['count']! as int,
    httpStatus: r['http_status'] as int?,
    error: r['error'] as String?,
    durationMs: r['duration_ms'] as int?,
  );

  final String batchId;
  final int sentAt;
  final int count;
  final int? httpStatus;
  final String? error;
  final int? durationMs;

  bool get ok => httpStatus == 200;
}

/// The local event queue (`event_queue`): written on every track, drained in
/// batches by the uploader. Each event has a client-generated `event_id`, so
/// a batch that is retried after a lost response is deduplicated server-side.
class EventQueue {
  EventQueue(this._db, {this._clock = systemClock, Random? random})
    : _random = random ?? Random();

  final DatabaseExecutor _db;
  final Clock _clock;
  final Random _random;

  static const maxAttempts = 8;
  static const baseBackoff = Duration(seconds: 5);
  static const maxBackoff = Duration(minutes: 10);

  /// Sent rows older than this are deleted to keep the table small.
  static const keepSent = Duration(days: 7);

  Future<void> add(QueuedEvent e) => _db.insert('event_queue', {
    'event_id': e.eventId,
    'name': e.name,
    'ts': e.ts,
    'session_id': e.sessionId,
    'seq': e.seq,
    'user_id': e.userId,
    'params': jsonEncode(e.params),
    'status': EventStatus.pending,
    'attempts': 0,
    'next_attempt_at': 0,
    'created_at': _clock(),
  }, conflictAlgorithm: ConflictAlgorithm.ignore);

  /// A batch left in "sending" by a killed process goes back to pending, so
  /// the next cold start re-sends it (the server dedupes by event_id).
  Future<int> recoverStuck() => _db.rawUpdate(
    'UPDATE event_queue SET status = ?, batch_id = NULL WHERE status = ?',
    [EventStatus.pending, EventStatus.sending],
  );

  /// Claims up to [limit] due events, oldest first, under [batchId].
  Future<List<QueuedEvent>> claim(String batchId, {int limit = 50}) async {
    final now = _clock();
    final rows = await _db.query(
      'event_queue',
      where: 'status = ? AND next_attempt_at <= ?',
      whereArgs: [EventStatus.pending, now],
      orderBy: 'ts, seq',
      limit: limit,
    );
    if (rows.isEmpty) return const [];
    final ids = [for (final r in rows) r['event_id']! as String];
    await _db.rawUpdate(
      'UPDATE event_queue SET status = ?, batch_id = ? '
      'WHERE event_id IN (${List.filled(ids.length, '?').join(', ')})',
      [EventStatus.sending, batchId, ...ids],
    );
    return rows.map(QueuedEvent.fromRow).toList();
  }

  Future<void> markSent(String batchId) => _db.rawUpdate(
    'UPDATE event_queue SET status = ? WHERE batch_id = ?',
    [EventStatus.sent, batchId],
  );

  /// Exponential backoff with ±20 % jitter: 5 s, 10 s, 20 s ... capped at
  /// 10 min; after [maxAttempts] the event is parked as dead.
  Future<void> markFailed(String batchId) async {
    final rows = await _db.query(
      'event_queue',
      columns: ['event_id', 'attempts'],
      where: 'batch_id = ?',
      whereArgs: [batchId],
    );
    final now = _clock();
    final batch = _db.batch();
    for (final r in rows) {
      final attempts = (r['attempts']! as int) + 1;
      batch.update(
        'event_queue',
        {
          'attempts': attempts,
          'batch_id': null,
          'status': attempts >= maxAttempts
              ? EventStatus.dead
              : EventStatus.pending,
          'next_attempt_at': now + backoff(attempts).inMilliseconds,
        },
        where: 'event_id = ?',
        whereArgs: [r['event_id']],
      );
    }
    await batch.commit(noResult: true);
  }

  Duration backoff(int attempts) {
    final raw = baseBackoff.inMilliseconds * pow(2, attempts - 1);
    final capped = min(raw.toDouble(), maxBackoff.inMilliseconds.toDouble());
    final jitter = 0.8 + _random.nextDouble() * 0.4;
    return Duration(milliseconds: (capped * jitter).round());
  }

  Future<void> logUpload(UploadRecord r) => _db.insert('upload_log', {
    'batch_id': r.batchId,
    'sent_at': r.sentAt,
    'count': r.count,
    'http_status': r.httpStatus,
    'error': r.error,
    'duration_ms': r.durationMs,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<int> purgeSent() => _db.delete(
    'event_queue',
    where: 'status = ? AND created_at < ?',
    whereArgs: [EventStatus.sent, _clock() - keepSent.inMilliseconds],
  );

  /// Status -> count, for the debug panel.
  Future<Map<int, int>> counts() async {
    final rows = await _db.rawQuery(
      'SELECT status, COUNT(*) AS n FROM event_queue GROUP BY status',
    );
    return {for (final r in rows) r['status']! as int: r['n']! as int};
  }

  Future<List<QueuedEvent>> recent({int? status, int limit = 50}) async {
    final rows = await _db.query(
      'event_queue',
      where: status == null ? null : 'status = ?',
      whereArgs: status == null ? null : [status],
      orderBy: 'ts DESC, seq DESC',
      limit: limit,
    );
    return rows.map(QueuedEvent.fromRow).toList();
  }

  Future<List<UploadRecord>> uploads({int limit = 20}) async {
    final rows = await _db.query(
      'upload_log',
      orderBy: 'sent_at DESC',
      limit: limit,
    );
    return rows.map(UploadRecord.fromRow).toList();
  }

  /// When the next pending event becomes due, or null if none is waiting.
  Future<int?> nextDueAt() async {
    final rows = await _db.rawQuery(
      'SELECT MIN(next_attempt_at) AS t FROM event_queue WHERE status = ?',
      [EventStatus.pending],
    );
    return rows.single['t'] as int?;
  }
}
