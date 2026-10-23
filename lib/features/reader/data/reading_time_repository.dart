import 'package:sqflite/sqflite.dart';

import '../../../core/clock.dart';

/// Accumulated reading time, stored as segments.
///
/// A segment is one continuous stretch of reading. The tracker rewrites its
/// running total (absolute ms, not a delta) every few seconds, so replaying or
/// retrying a write can never double-count.
class ReadingTimeRepository {
  ReadingTimeRepository(this._db, {this._clock = systemClock});

  final DatabaseExecutor _db;
  final Clock _clock;

  Future<void> saveSegment({
    required String segmentId,
    required String userId,
    required String articleId,
    required String sessionId,
    required int startedAt,
    required int activeMs,
  }) {
    return _db.rawInsert(
      '''
      INSERT INTO reading_segments (segment_id, user_id, article_id, session_id,
        started_at, active_ms, local_day, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(segment_id) DO UPDATE SET
        active_ms = MAX(reading_segments.active_ms, excluded.active_ms),
        updated_at = excluded.updated_at''',
      [
        segmentId,
        userId,
        articleId,
        sessionId,
        startedAt,
        activeMs,
        localDay(startedAt),
        _clock(),
      ],
    );
  }

  Future<int> totalActiveMs(String userId, String articleId) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(active_ms), 0) AS total FROM reading_segments '
      'WHERE user_id = ? AND article_id = ?',
      [userId, articleId],
    );
    return rows.first['total']! as int;
  }

  /// Device-local calendar day, e.g. `2026-10-23`; used for daily stats.
  static String localDay(int epochMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}
