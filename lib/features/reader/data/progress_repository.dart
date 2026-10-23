import 'package:sqflite/sqflite.dart';

import '../../../core/clock.dart';

class ReadingStatus {
  static const unread = 0;
  static const reading = 1;
  static const finished = 2;
}

/// Where the reader was and how far they got in one article.
class ReadingPosition {
  const ReadingPosition({
    required this.scrollOffset,
    required this.anchorPara,
    required this.anchorDelta,
    required this.fontScale,
    required this.progress,
  });

  /// Pixel offset; exact when the font scale is unchanged.
  final double scrollOffset;

  /// Paragraph index + fraction inside it; used when the font scale changed.
  final int anchorPara;
  final double anchorDelta;
  final double fontScale;

  /// 0..1 share of the article seen so far at this position.
  final double progress;
}

class ReadingProgress {
  const ReadingProgress({
    required this.position,
    required this.maxProgress,
    required this.status,
    required this.finishedAt,
    required this.lastReadAt,
    required this.updatedAt,
  });

  factory ReadingProgress.fromRow(Map<String, Object?> row) {
    double real(String column) => (row[column]! as num).toDouble();
    return ReadingProgress(
      position: ReadingPosition(
        scrollOffset: real('scroll_offset'),
        anchorPara: row['anchor_para']! as int,
        anchorDelta: real('anchor_delta'),
        fontScale: real('font_scale'),
        progress: real('progress'),
      ),
      maxProgress: real('max_progress'),
      status: row['status']! as int,
      finishedAt: row['finished_at'] as int?,
      lastReadAt: row['last_read_at']! as int,
      updatedAt: row['updated_at']! as int,
    );
  }

  final ReadingPosition position;
  final double maxProgress;
  final int status;
  final int? finishedAt;
  final int lastReadAt;
  final int updatedAt;
}

class ProgressRepository {
  ProgressRepository(this._db, {this._clock = systemClock});

  final DatabaseExecutor _db;
  final Clock _clock;

  /// Idempotent upsert of the latest reading position.
  ///
  /// Position follows the newest write; a write stamped older than the stored
  /// row is ignored, so a late flush can never move the reader backwards.
  /// `max_progress` and `status` only ever grow.
  Future<void> save(String userId, String articleId, ReadingPosition pos) {
    final now = _clock();
    return _db.rawInsert(
      '''
      INSERT INTO reading_progress (user_id, article_id, scroll_offset,
        anchor_para, anchor_delta, font_scale, progress, max_progress, status,
        last_read_at, dirty, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)
      ON CONFLICT(user_id, article_id) DO UPDATE SET
        scroll_offset = excluded.scroll_offset,
        anchor_para = excluded.anchor_para,
        anchor_delta = excluded.anchor_delta,
        font_scale = excluded.font_scale,
        progress = excluded.progress,
        max_progress = MAX(reading_progress.max_progress, excluded.max_progress),
        status = MAX(reading_progress.status, excluded.status),
        last_read_at = MAX(reading_progress.last_read_at, excluded.last_read_at),
        dirty = 1,
        updated_at = excluded.updated_at
      WHERE excluded.updated_at >= reading_progress.updated_at''',
      [
        userId,
        articleId,
        pos.scrollOffset,
        pos.anchorPara,
        pos.anchorDelta,
        pos.fontScale,
        pos.progress,
        pos.progress,
        ReadingStatus.reading,
        now,
        now,
      ],
    );
  }

  /// Marks the article finished. Returns true only on the transition, so the
  /// caller can play the celebration exactly once.
  Future<bool> markFinished(String userId, String articleId) async {
    final now = _clock();
    final changed = await _db.rawUpdate(
      '''
      UPDATE reading_progress
      SET status = ?, finished_at = ?, max_progress = MAX(max_progress, 1.0),
        dirty = 1, updated_at = ?
      WHERE user_id = ? AND article_id = ? AND status < ?''',
      [
        ReadingStatus.finished,
        now,
        now,
        userId,
        articleId,
        ReadingStatus.finished,
      ],
    );
    return changed == 1;
  }

  Future<ReadingProgress?> get(String userId, String articleId) async {
    final rows = await _db.query(
      'reading_progress',
      where: 'user_id = ? AND article_id = ?',
      whereArgs: [userId, articleId],
    );
    return rows.isEmpty ? null : ReadingProgress.fromRow(rows.first);
  }
}
