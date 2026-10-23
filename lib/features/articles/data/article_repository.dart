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
  );

  final String id;
  final String title;
  final String summary;
  final String cover;
  final String category;
  final int level;
  final int wordCount;
  final int publishedAt;
}

class ArticleRepository {
  ArticleRepository(this._db);

  final DatabaseExecutor _db;

  static const _summaryColumns = [
    'id',
    'title',
    'summary',
    'cover',
    'category',
    'level',
    'word_count',
    'published_at',
  ];

  /// Newest first; ties broken by id so the order is stable for paging.
  Future<List<ArticleSummary>> list() async {
    final rows = await _db.query(
      'articles',
      columns: _summaryColumns,
      orderBy: 'published_at DESC, id DESC',
    );
    return rows.map(ArticleSummary.fromRow).toList();
  }

  Future<List<String>> paragraphs(String id) async {
    final rows = await _db.query(
      'articles',
      columns: ['body'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return const [];
    return (jsonDecode(rows.single['body']! as String) as List).cast<String>();
  }
}
