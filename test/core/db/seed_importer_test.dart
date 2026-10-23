import 'dart:io';

import 'package:english_reader/core/db/seed_importer.dart';
import 'package:english_reader/features/vocab/data/dictionary_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_db.dart';

void main() {
  // The real bundled seed, read from disk (tests run from the package root).
  final realSeed = SeedBundle.fromJson(
    articlesJson: File('assets/seed/articles.json').readAsStringSync(),
    dictJson: File('assets/seed/dict.json').readAsStringSync(),
  );

  test(
    'imports the bundled seed once and is a no-op the second time',
    () async {
      final db = await openTestDb();

      expect(await SeedImporter.importIfNeeded(db, realSeed), isTrue);
      final articles = await db.rawQuery('SELECT COUNT(*) AS n FROM articles');
      expect(articles.single['n'], realSeed.articles.length);
      expect(await SeedImporter.installedVersion(db), realSeed.version);

      expect(await SeedImporter.importIfNeeded(db, realSeed), isFalse);
      final again = await db.rawQuery('SELECT COUNT(*) AS n FROM articles');
      expect(again.single['n'], realSeed.articles.length);
    },
  );

  test('every category x level cell has at least two articles', () async {
    final db = await openTestDb();
    await SeedImporter.importIfNeeded(db, realSeed);
    final cells = await db.rawQuery(
      'SELECT category, level, COUNT(*) AS n FROM articles '
      'GROUP BY category, level',
    );
    expect(cells, hasLength(12));
    expect(cells.every((c) => (c['n']! as int) >= 2), isTrue);
  });

  test('dictionary resolves inflections to their headword', () async {
    final db = await openTestDb();
    await SeedImporter.importIfNeeded(db, realSeed);
    final dict = DictionaryRepository(db);

    final bought = await dict.lookup('Bought');
    expect(bought?.lemma, 'buy');
    expect(bought?.word, 'bought');
    expect(await dict.lookup('zzzzqx'), isNull);
  });

  test(
    'a newer seed only overwrites articles with a newer content_version',
    () async {
      final db = await openTestDb();
      await SeedImporter.importIfNeeded(
        db,
        _seed(version: 1, contentVersion: 1, title: 'v1'),
      );

      // Same content_version: the title must not change even though the seed did.
      await SeedImporter.importIfNeeded(
        db,
        _seed(version: 2, contentVersion: 1, title: 'other'),
      );
      expect(await _title(db), 'v1');

      await SeedImporter.importIfNeeded(
        db,
        _seed(version: 3, contentVersion: 2, title: 'v2'),
      );
      expect(await _title(db), 'v2');
    },
  );

  test('a failed import rolls back completely', () async {
    final db = await openTestDb();
    final broken = SeedBundle(
      version: 1,
      articles: [
        _article(contentVersion: 1, title: 'ok'),
        // Violates CHECK (level BETWEEN 1 AND 3).
        {..._article(contentVersion: 1, title: 'bad'), 'id': 'bad', 'level': 9},
      ],
      dictEntries: const [],
      wordForms: const {},
    );

    await expectLater(
      SeedImporter.importIfNeeded(db, broken),
      throwsA(anything),
    );
    final n = await db.rawQuery('SELECT COUNT(*) AS n FROM articles');
    expect(n.single['n'], 0);
    expect(await SeedImporter.installedVersion(db), isNull);
  });
}

Map<String, dynamic> _article({
  required int contentVersion,
  required String title,
}) => {
  'id': 'a1',
  'title': title,
  'summary': 's',
  'cover': 'g0',
  'category': 'daily',
  'level': 1,
  'published_at': 0,
  'word_count': 1,
  'content_version': contentVersion,
  'paragraphs': ['Hi.'],
};

SeedBundle _seed({
  required int version,
  required int contentVersion,
  required String title,
}) => SeedBundle(
  version: version,
  articles: [_article(contentVersion: contentVersion, title: title)],
  dictEntries: const [],
  wordForms: const {},
);

Future<String> _title(Database db) async {
  final rows = await db.query('articles', columns: ['title']);
  return rows.single['title']! as String;
}
