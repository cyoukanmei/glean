import 'package:sqflite/sqflite.dart';

import '../../../core/clock.dart';
import '../../articles/data/article_repository.dart';

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

  /// The article read most recently and not finished yet, for the
  /// "continue reading" card.
  Future<(String articleId, ReadingProgress progress)?> lastUnfinished(
    String userId,
  ) async {
    final rows = await _db.query(
      'reading_progress',
      where: 'user_id = ? AND status = ?',
      whereArgs: [userId, ReadingStatus.reading],
      orderBy: 'last_read_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return (row['article_id']! as String, ReadingProgress.fromRow(row));
  }

  /// Reading history: every article this user opened, most recent first.
  Future<List<(ArticleSummary, ReadingProgress)>> history(
    String userId, {
    int limit = 200,
  }) async {
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, a.id, a.title, a.summary, a.cover, a.category, a.level,
        a.word_count, a.published_at, a.author, a.readers, a.favorites
      FROM reading_progress p JOIN articles a ON a.id = p.article_id
      WHERE p.user_id = ?
      ORDER BY p.last_read_at DESC
      LIMIT ?''',
      [userId, limit],
    );
    return [
      for (final r in rows)
        (ArticleSummary.fromRow(r), ReadingProgress.fromRow(r)),
    ];
  }

  /// Furthest progress and status per article, for list cards.
  Future<Map<String, (double maxProgress, int status)>> forArticles(
    String userId,
    Iterable<String> articleIds,
  ) async {
    final ids = articleIds.toList();
    if (ids.isEmpty) return {};
    final rows = await _db.query(
      'reading_progress',
      columns: ['article_id', 'max_progress', 'status'],
      where:
          'user_id = ? AND article_id IN (${List.filled(ids.length, '?').join(', ')})',
      whereArgs: [userId, ...ids],
    );
    return {
      for (final r in rows)
        r['article_id']! as String: (
          (r['max_progress']! as num).toDouble(),
          r['status']! as int,
        ),
    };
  }

  /// Number of articles this user has finished.
  Future<int> finishedCount(String userId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM reading_progress '
      'WHERE user_id = ? AND status = ?',
      [userId, ReadingStatus.finished],
    );
    return rows.single['n']! as int;
  }
}
