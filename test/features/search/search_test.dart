import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/core/db/seed_importer.dart';
import 'package:glean/features/articles/data/article_repository.dart';
import 'package:glean/features/search/search_page.dart';

import '../../helpers/test_db.dart';

Future<ArticleRepository> _seeded() async {
  final db = await openTestDb();
  await SeedImporter.importIfNeeded(
    db,
    SeedBundle.fromJson(
      articlesJson: File('assets/seed/articles.json').readAsStringSync(),
      dictJson: File('assets/seed/dict.json').readAsStringSync(),
    ),
  );
  return ArticleRepository(db);
}

void main() {
  test('title matches rank first; body matches carry a snippet and the '
      'exact position', () async {
    final repo = await _seeded();
    final hits = await repo.search('PHONE');
    expect(hits.first.inTitle, isTrue);
    final firstBodyOnly = hits.indexWhere((h) => !h.inTitle);
    expect(firstBodyOnly, greaterThan(0), reason: 'body-only hits exist');
    expect(
      hits.skip(firstBodyOnly).every((h) => !h.inTitle),
      isTrue,
      reason: 'title matches come first',
    );

    for (final h in hits.where((h) => h.paragraph != null)) {
      final paragraphs = await repo.paragraphs(h.article.id);
      final p = paragraphs[h.paragraph!];
      expect(
        p.substring(h.matchStart!, h.matchStart! + 5).toLowerCase(),
        'phone',
      );
      expect(h.snippet!.toLowerCase(), contains('phone'));
    }
  });

  test('body-only matches find classics', () async {
    final repo = await _seeded();
    final hits = await repo.search('rabbit-hole');
    expect(
      hits.map((h) => h.article.id),
      contains('classic-alice-in-wonderland-1'),
    );
    expect(hits.every((h) => !h.inTitle), isTrue);
  });

  test(
    'blank and absent queries return nothing; LIKE wildcards are literal',
    () async {
      final repo = await _seeded();
      expect(await repo.search('   '), isEmpty);
      expect(await repo.search('zzqxw'), isEmpty);
      expect(await repo.search('%'), isEmpty);
    },
  );

  test('highlight marks every case-insensitive occurrence', () {
    const mark = TextStyle(fontWeight: FontWeight.w700);
    final spans = highlight('Tea, tea and TEA.', 'tea', mark);
    expect(spans.map((s) => s.text), ['Tea', ', ', 'tea', ' and ', 'TEA', '.']);
    expect(spans.where((s) => s.style == mark), hasLength(3));
    expect(highlight('abc', '', mark).single.text, 'abc');
  });

  test('history keeps the newest ten, without duplicates', () async {
    var stored = <String>[];
    final history = SearchHistory(() => stored, (v) async => stored = v);
    for (var i = 0; i < 12; i++) {
      await history.add('q$i');
    }
    await history.add('Q5');
    expect(history.items.first, 'Q5');
    expect(history.items, hasLength(10));
    expect(history.items.where((q) => q.toLowerCase() == 'q5'), hasLength(1));
    await history.clear();
    expect(history.items, isEmpty);
  });
}
