import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Parsed contents of `assets/seed/articles.json` and `assets/seed/dict.json`.
class SeedBundle {
  const SeedBundle({
    required this.version,
    required this.articles,
    required this.dictEntries,
    required this.wordForms,
  });

  factory SeedBundle.fromJson({
    required String articlesJson,
    required String dictJson,
  }) {
    final a = jsonDecode(articlesJson) as Map<String, dynamic>;
    final d = jsonDecode(dictJson) as Map<String, dynamic>;
    return SeedBundle(
      version: a['seed_version'] as int,
      articles: (a['articles'] as List).cast<Map<String, dynamic>>(),
      dictEntries: (d['entries'] as List).cast<List<dynamic>>(),
      wordForms: (d['forms'] as Map).cast<String, String>(),
    );
  }

  final int version;
  final List<Map<String, dynamic>> articles;

  /// Each entry is `[word, phonetic, definition]`.
  final List<List<dynamic>> dictEntries;
  final Map<String, String> wordForms;
}

abstract final class SeedImporter {
  static const _versionKey = 'seed_version';

  /// Imports [seed] once per seed version, in a single transaction.
  ///
  /// Returns false when this seed version (or a newer one) is already in.
  /// Articles only overwrite older `content_version`s, and user tables are
  /// never touched, so re-running after an app update is safe.
  static Future<bool> importIfNeeded(Database db, SeedBundle seed) async {
    final current = await installedVersion(db);
    if (current != null && current >= seed.version) return false;

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final a in seed.articles) {
        final paragraphs = (a['paragraphs'] as List).cast<String>();
        batch.rawInsert(
          '''
          INSERT INTO articles (id, title, summary, cover, category, level,
            body, word_count, published_at, content_version, author,
            readers, favorites)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            title = excluded.title, summary = excluded.summary,
            cover = excluded.cover, category = excluded.category,
            level = excluded.level, body = excluded.body,
            word_count = excluded.word_count,
            published_at = excluded.published_at,
            content_version = excluded.content_version,
            author = excluded.author
          WHERE excluded.content_version > articles.content_version''',
          [
            a['id'],
            a['title'],
            a['summary'],
            a['cover'],
            a['category'],
            a['level'],
            jsonEncode(paragraphs),
            a['word_count'],
            a['published_at'],
            a['content_version'] ?? 1,
            a['author'],
            a['readers'] ?? 0,
            a['favorites'] ?? 0,
          ],
        );
        // Stats change without a content change, so they always refresh.
        batch.rawUpdate(
          'UPDATE articles SET readers = ?, favorites = ? WHERE id = ?',
          [a['readers'] ?? 0, a['favorites'] ?? 0, a['id']],
        );
      }
      for (final e in seed.dictEntries) {
        batch.rawInsert(
          'INSERT OR REPLACE INTO dict (word, phonetic, definition) '
          'VALUES (?, ?, ?)',
          e,
        );
      }
      seed.wordForms.forEach((form, lemma) {
        batch.rawInsert(
          'INSERT OR REPLACE INTO word_forms (form, lemma) VALUES (?, ?)',
          [form, lemma],
        );
      });
      batch.rawInsert(
        'INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)',
        [_versionKey, '${seed.version}'],
      );
      await batch.commit(noResult: true);
    });
    return true;
  }

  static Future<int?> installedVersion(DatabaseExecutor db) async {
    final rows = await db.query(
      'app_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_versionKey],
    );
    return rows.isEmpty ? null : int.parse(rows.first['value']! as String);
  }
}
