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
    this.readers = 0,
    this.favorites = 0,
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
    readers: row['readers'] as int? ?? 0,
    favorites: row['favorites'] as int? ?? 0,
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

  /// How many people read / starred it (community stats from the server;
  /// mock numbers from the seed here).
  final int readers;
  final int favorites;

  /// Keyset position of this article in the feed order.
  FeedCursor get cursor => FeedCursor(publishedAt, id);
}

/// One search result: where the query matched and a snippet around it.
class SearchHit {
  const SearchHit({
    required this.article,
    required this.inTitle,
    required this.count,
    this.paragraph,
    this.matchStart,
    this.snippet,
    this.snippetOffset = 0,
  });

  final ArticleSummary article;
  final bool inTitle;

  /// Occurrences in the body.
  final int count;

  /// First body match: paragraph index and offset in that paragraph.
  final int? paragraph;
  final int? matchStart;

  /// Text around the first body match (with … where cut).
  final String? snippet;

  /// Offset of [snippet]'s first character in the paragraph, minus the
  /// leading ellipsis if any.
  final int snippetOffset;
}

/// 书城 rankings: most read, most starred, newest.
enum RankBoard {
  reading('热读榜'),
  favorites('收藏榜'),
  newest('新书榜');

  const RankBoard(this.label);

  final String label;
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
    'readers',
    'favorites',
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

  /// Full-text search over title, summary and body, case-insensitive.
  ///
  /// SQLite narrows the candidates (LIKE on the stored text); ranking and
  /// snippets are done here: title matches first, then by how often the
  /// body mentions the query, then newest.
  Future<List<SearchHit>> search(String query, {int limit = 30}) async {
    await _ready;
    final q = query.trim();
    if (q.isEmpty) return const [];
    final like = '%${q.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final rows = await _db.query(
      'articles',
      columns: [..._summaryColumns, 'body'],
      where:
          r"title LIKE ? ESCAPE '\' OR summary LIKE ? ESCAPE '\' "
          r"OR body LIKE ? ESCAPE '\'",
      whereArgs: [like, like, like],
    );
    final needle = q.toLowerCase();
    final hits = <SearchHit>[];
    for (final row in rows) {
      final article = ArticleSummary.fromRow(row);
      final paragraphs = (jsonDecode(row['body']! as String) as List)
          .cast<String>();
      var count = 0;
      int? para;
      int? at;
      for (final (i, p) in paragraphs.indexed) {
        final lower = p.toLowerCase();
        var from = lower.indexOf(needle);
        if (from >= 0 && para == null) {
          para = i;
          at = from;
        }
        while (from >= 0) {
          count++;
          from = lower.indexOf(needle, from + needle.length);
        }
      }
      final inTitle = article.title.toLowerCase().contains(needle);
      if (!inTitle &&
          count == 0 &&
          !article.summary.toLowerCase().contains(needle)) {
        continue; // matched only JSON escaping in the stored body
      }
      String? snippet;
      var offset = 0;
      if (para != null) {
        final p = paragraphs[para];
        final start = (at! - 40).clamp(0, p.length);
        final end = (at + needle.length + 60).clamp(0, p.length);
        snippet =
            '${start > 0 ? '…' : ''}${p.substring(start, end)}'
            '${end < p.length ? '…' : ''}';
        offset = start - (start > 0 ? 1 : 0);
      }
      hits.add(
        SearchHit(
          article: article,
          inTitle: inTitle,
          count: count,
          paragraph: para,
          matchStart: at,
          snippet: snippet,
          snippetOffset: offset,
        ),
      );
    }
    hits.sort((a, b) {
      if (a.inTitle != b.inTitle) return a.inTitle ? -1 : 1;
      if (a.count != b.count) return b.count.compareTo(a.count);
      return b.article.publishedAt.compareTo(a.article.publishedAt);
    });
    return hits.take(limit).toList();
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

  /// Top [limit] articles of a [board] (书城 rankings).
  Future<List<ArticleSummary>> ranking(
    RankBoard board, {
    int limit = 20,
  }) async {
    await _ready;
    final rows = await _db.query(
      'articles',
      columns: _summaryColumns,
      orderBy: switch (board) {
        RankBoard.reading => 'readers DESC, id',
        RankBoard.favorites => 'favorites DESC, id',
        RankBoard.newest => 'published_at DESC, id DESC',
      },
      limit: limit,
    );
    return rows.map(ArticleSummary.fromRow).toList();
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
          body, word_count, published_at, content_version, readers,
          favorites)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
          a['readers'] ?? 0,
          a['favorites'] ?? 0,
        ],
      );
    }
    await batch.commit(noResult: true);
  }
}
