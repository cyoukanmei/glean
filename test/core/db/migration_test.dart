import 'package:glean/core/db/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_db.dart';

void main() {
  test('v1 -> v2 adds vocab.status and keeps existing rows', () async {
    final path = await newTestDbPath();

    final v1 = await openTestDb(version: 1, path: path);
    await v1.insert('vocab', {
      'id': 'v1-row',
      'user_id': 'u1',
      'word': 'bought',
      'lemma': 'buy',
      'definition': 'vt. 买',
      'article_id': 'tech-1-a',
      'para_index': 0,
      'char_start': 4,
      'char_end': 10,
      'created_at': 1,
      'updated_at': 1,
    });
    expect(await v1.getVersion(), 1);
    await v1.close();

    final v2 = await openTestDb(path: path);
    expect(await v2.getVersion(), kSchemaVersion);
    final rows = await v2.query('vocab');
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'v1-row');
    expect(rows.single['status'], 0);
  });

  test(
    'v2 -> v3 rebuilds articles for classics and keeps reading progress',
    () async {
      final path = await newTestDbPath();
      final v2 = await openTestDb(version: 2, path: path);
      await insertArticle(v2, 'tech-1-a');
      await v2.insert('reading_progress', {
        'user_id': 'u1',
        'article_id': 'tech-1-a',
        'max_progress': 0.5,
        'last_read_at': 1,
        'updated_at': 1,
      });
      await v2.close();

      final v3 = await openTestDb(path: path);
      expect((await v3.query('articles')).single['id'], 'tech-1-a');
      expect((await v3.query('reading_progress')).single['max_progress'], 0.5);
      expect(await v3.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      await v3.insert('articles', {
        'id': 'classic-x-1',
        'title': 'X',
        'category': 'classic',
        'level': 3,
        'body': '["A."]',
        'word_count': 1,
        'published_at': 0,
        'author': 'Someone',
      });
      // The rebuilt table is still the parent of reading_progress.
      await expectLater(
        v3.insert('reading_progress', {
          'user_id': 'u1',
          'article_id': 'missing',
          'last_read_at': 1,
          'updated_at': 1,
        }),
        throwsA(isA<DatabaseException>()),
      );
      final users = await v3.rawQuery('PRAGMA table_info(users)');
      expect(
        users.map((c) => c['name']),
        containsAll(['display_name', 'avatar', 'bio', 'daily_goal_min']),
      );
    },
  );

  test(
    'fresh install and upgraded database end up with the same schema',
    () async {
      final upgradedPath = await newTestDbPath();
      await (await openTestDb(version: 1, path: upgradedPath)).close();
      final upgraded = await openTestDb(path: upgradedPath);
      final fresh = await openTestDb();

      Future<List<String>> schemaOf(Database db) async {
        final rows = await db.rawQuery(
          "SELECT name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' "
          'ORDER BY name',
        );
        return [for (final r in rows) '${r['name']}: ${r['sql']}'];
      }

      expect(await schemaOf(upgraded), await schemaOf(fresh));
    },
  );

  test('pragmas: WAL journal and foreign keys are on', () async {
    final db = await openTestDb();
    final journal = await db.rawQuery('PRAGMA journal_mode');
    final fk = await db.rawQuery('PRAGMA foreign_keys');
    expect(journal.single.values.single, 'wal');
    expect(fk.single.values.single, 1);
  });
}
