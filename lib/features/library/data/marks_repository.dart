import 'package:sqflite/sqflite.dart';

import '../../../core/clock.dart';
import '../../articles/data/article_repository.dart';

/// What a mark means.
enum MarkKind {
  favorite('收藏'),
  later('稍后再读');

  const MarkKind(this.label);

  final String label;
}

/// Articles the user starred (收藏) or saved for later (稍后再读).
///
/// One row per (user, article, kind). Removing keeps a tombstone
/// (`deleted_at`) and marking again revives it, so the change syncs like
/// any other edit (last write wins).
class MarksRepository {
  MarksRepository(this._db, {this._clock = systemClock});

  final DatabaseExecutor _db;
  final Clock _clock;

  Future<void> set(
    String userId,
    String articleId,
    MarkKind kind, {
    required bool on,
  }) {
    final now = _clock();
    if (on) {
      return _db.rawInsert(
        '''
        INSERT INTO article_marks (user_id, article_id, kind, created_at,
          updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(user_id, article_id, kind) DO UPDATE SET
          created_at = excluded.created_at, updated_at = excluded.updated_at,
          deleted_at = NULL, dirty = 1
        WHERE article_marks.deleted_at IS NOT NULL''',
        [userId, articleId, kind.name, now, now],
      );
    }
    return _db.rawUpdate(
      'UPDATE article_marks SET deleted_at = ?, updated_at = ?, dirty = 1 '
      'WHERE user_id = ? AND article_id = ? AND kind = ? '
      'AND deleted_at IS NULL',
      [now, now, userId, articleId, kind.name],
    );
  }

  /// The kinds currently set on [articleId].
  Future<Set<MarkKind>> of(String userId, String articleId) async {
    final rows = await _db.query(
      'article_marks',
      columns: ['kind'],
      where: 'user_id = ? AND article_id = ? AND deleted_at IS NULL',
      whereArgs: [userId, articleId],
    );
    return {for (final r in rows) MarkKind.values.byName(r['kind']! as String)};
  }

  /// Marked articles, most recently marked first.
  Future<List<(ArticleSummary, int markedAt)>> list(
    String userId,
    MarkKind kind,
  ) async {
    final rows = await _db.rawQuery(
      '''
      SELECT a.id, a.title, a.summary, a.cover, a.category, a.level,
        a.word_count, a.published_at, a.author, a.readers, a.favorites,
        m.created_at AS marked_at
      FROM article_marks m JOIN articles a ON a.id = m.article_id
      WHERE m.user_id = ? AND m.kind = ? AND m.deleted_at IS NULL
      ORDER BY m.created_at DESC''',
      [userId, kind.name],
    );
    return [
      for (final r in rows) (ArticleSummary.fromRow(r), r['marked_at']! as int),
    ];
  }

  /// Kind -> number of marked articles.
  Future<Map<MarkKind, int>> counts(String userId) async {
    final rows = await _db.rawQuery(
      'SELECT kind, COUNT(*) AS n FROM article_marks '
      'WHERE user_id = ? AND deleted_at IS NULL GROUP BY kind',
      [userId],
    );
    return {
      for (final r in rows)
        MarkKind.values.byName(r['kind']! as String): r['n']! as int,
    };
  }
}
