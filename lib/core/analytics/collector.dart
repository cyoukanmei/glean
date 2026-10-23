import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../clock.dart';

/// What an upload returned.
class CollectorResponse {
  const CollectorResponse(
    this.status, {
    this.accepted = 0,
    this.duplicates = 0,
  });

  final int status;
  final int accepted;

  /// Events already received in an earlier (retried) batch.
  final int duplicates;
}

/// Thrown when there is no network.
class OfflineException implements Exception {
  const OfflineException();

  @override
  String toString() => 'offline';
}

/// Stand-in for the analytics backend's `POST /v1/events`.
///
/// It stores into `collected_events` (the "warehouse"), keyed by event_id,
/// so a batch re-sent after a lost response is counted once. Failures can be
/// injected from the debug panel to watch backoff and retry at work.
class MockCollector {
  MockCollector(
    this._db, {
    required this.isOnline,
    this._clock = systemClock,
    this.latency = const Duration(milliseconds: 250),
  });

  final DatabaseExecutor _db;
  final Clock _clock;
  final bool Function() isOnline;
  final Duration latency;

  /// Debug: answer every upload with 503.
  bool failUploads = false;

  /// Request body: `{"batch_id": ..., "events": [...]}`.
  Future<CollectorResponse> post(String body) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (!isOnline()) throw const OfflineException();
    if (failUploads) return const CollectorResponse(503);

    final json = jsonDecode(body) as Map<String, dynamic>;
    final events = (json['events'] as List).cast<Map<String, dynamic>>();
    final now = _clock();
    final ids = [for (final e in events) e['event_id'] as String];
    final seen = ids.isEmpty
        ? const <String>{}
        : {
            for (final r in await _db.query(
              'collected_events',
              columns: ['event_id'],
              where: 'event_id IN (${List.filled(ids.length, '?').join(', ')})',
              whereArgs: ids,
            ))
              r['event_id']! as String,
          };
    final batch = _db.batch();
    var accepted = 0;
    for (final e in events) {
      if (seen.contains(e['event_id'])) continue;
      accepted++;
      batch.rawInsert(
        'INSERT OR IGNORE INTO collected_events '
        '(event_id, name, ts, session_id, user_id, params, received_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          e['event_id'],
          e['name'],
          e['ts'],
          e['session_id'],
          e['user_id'],
          jsonEncode(e['params']),
          now,
        ],
      );
    }
    await batch.commit(noResult: true);
    return CollectorResponse(
      200,
      accepted: accepted,
      duplicates: events.length - accepted,
    );
  }
}
