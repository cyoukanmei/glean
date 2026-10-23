import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Everything a list card needs; enough to build the reader's header on the
/// first frame so the cover Hero has a destination immediately.
class ArticleSummary {
  const ArticleSummary({
    required this.id,
    required this.title,
    required this.summary,
    required this.cover,
    required this.category,
    required this.level,
    required this.wordCount,
    required this.publishedAt,
    this.author,
  });

  factory ArticleSummary.fromRow(Map<String, Object?> row) => ArticleSummary(
    id: row['id']! as String,
    title: row['title']! as String,
    summary: row['summary'] as String? ?? '',
    cover: row['cover'] as String? ?? 'g0',
    category: row['category']! as String,
    level: row['level']! as int,
    wordCount: row['word_count']! as int,
    publishedAt: row['published_at']! as int,
    author: row['author'] as String?,
  );

  final String id;
  final String title;
  final String summary;
  final String cover;
  final String category;
  final int level;
  final int wordCount;
  final int publishedAt;

  /// Set for classic novels.
  final String? author;

  /// Keyset position of this article in the feed order.
  FeedCursor get cursor => FeedCursor(publishedAt, id);
}

/// Position after which the next feed page starts.
///
/// Keyset (seek) pagination instead of OFFSET: pages stay stable when new
/// articles are inserted at the top by a refresh, and each page is an index
/// range scan regardless of depth.
class FeedCursor {
  const FeedCursor(this.publishedAt, this.id);

  final int publishedAt;
  final String id;
}

class ArticleRepository {
  ArticleRepository(this._db, {this._ready});

  final DatabaseExecutor _db;

  /// Completes once the seed import has finished; reads wait for it so the
  /// UI can start (and show skeletons) before the first launch import ends.
  final Future<void>? _ready;

  static const _summaryColumns = [
    'id',
    'title',
    'summary',
    'cover',
    'category',
    'level',
    'word_count',
    'published_at',
    'author',
  ];

  /// One feed page, newest first (ties broken by id).
  ///
  /// [category] null means all categories; empty [levels] means all levels;
  /// [query] matches title or summary, case-insensitively.
  Future<List<ArticleSummary>> page({
    String? category,
    Set<int> levels = const {},
    String query = '',
    FeedCursor? after,
    int limit = 10,
  }) async {
    await _ready;
    final where = <String>[];
    final args = <Object?>[];
    if (category != null) {
      where.add('category = ?');
      args.add(category);
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      final like = '%${q.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      where.add(r"(title LIKE ? ESCAPE '\' OR summary LIKE ? ESCAPE '\')");
      args.addAll([like, like]);
    }
    if (levels.isNotEmpty) {
      where.add('level IN (${List.filled(levels.length, '?').join(', ')})');
      args.addAll(levels);
    }
    if (after != null) {
      where.add('(published_at < ? OR (published_at = ? AND id < ?))');
      args.addAll([after.publishedAt, after.publishedAt, after.id]);
    }
    final rows = await _db.query(
      'articles',
      columns: _summaryColumns,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'published_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(ArticleSummary.fromRow).toList();
  }

  /// The article next to [article] in feed order: the newer one (shown above
  /// it) or the older one (below). Drives the reader's 上一篇 / 下一篇.
  Future<ArticleSummary?> neighbor(
    ArticleSummary article, {
    required bool newer,
  }) async {
    await _ready;
    final rows = await _db.query(
      'articles',
      columns: _summaryColumns,
      where: newer
          ? '(published_at > ? OR (published_at = ? AND id > ?))'
          : '(published_at < ? OR (published_at = ? AND id < ?))',
      whereArgs: [article.publishedAt, article.publishedAt, article.id],
      orderBy: newer
          ? 'published_at ASC, id ASC'
          : 'published_at DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : ArticleSummary.fromRow(rows.single);
  }

  /// Articles stored on the device (all readable offline).
  Future<int> count() async {
    await _ready;
    final rows = await _db.rawQuery('SELECT COUNT(*) AS n FROM articles');
    return rows.single['n']! as int;
  }

  Future<ArticleSummary?> byId(String id) async {
    await _ready;
    final rows = await _db.query(
      'articles',
      columns: _summaryColumns,
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : ArticleSummary.fromRow(rows.single);
  }

  Future<List<String>> paragraphs(String id) async {
    await _ready;
    final rows = await _db.query(
      'articles',
      columns: ['body'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return const [];
    return (jsonDecode(rows.single['body']! as String) as List).cast<String>();
  }

  Future<Set<String>> knownIds(Iterable<String> ids) async {
    await _ready;
    final list = ids.toList();
    if (list.isEmpty) return {};
    final rows = await _db.query(
      'articles',
      columns: ['id'],
      where: 'id IN (${List.filled(list.length, '?').join(', ')})',
      whereArgs: list,
    );
    return {for (final r in rows) r['id']! as String};
  }

  /// Stores articles fetched from the server. Idempotent: re-inserting an
  /// article keeps the stored copy unless the server's content is newer.
  Future<void> upsertAll(List<Map<String, Object?>> articles) async {
    await _ready;
    final batch = _db.batch();
    for (final a in articles) {
      batch.rawInsert(
        '''
        INSERT INTO articles (id, title, summary, cover, category, level,
          body, word_count, published_at, content_version)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title, summary = excluded.summary,
          cover = excluded.cover, category = excluded.category,
          level = excluded.level, body = excluded.body,
          word_count = excluded.word_count,
          content_version = excluded.content_version
        WHERE excluded.content_version > articles.content_version''',
        [
          a['id'],
          a['title'],
          a['summary'],
          a['cover'],
          a['category'],
          a['level'],
          jsonEncode(a['paragraphs']),
          a['word_count'],
          a['published_at'],
          a['content_version'] ?? 1,
        ],
      );
    }
    await batch.commit(noResult: true);
  }
}
