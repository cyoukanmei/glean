import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glean/core/db/seed_importer.dart';
import 'package:glean/features/articles/data/article_remote.dart';
import 'package:glean/features/articles/data/article_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_db.dart';

Future<ArticleRepository> _seededRepo() async {
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

Future<List<ArticleSummary>> _readAll(
  ArticleRepository repo, {
  String? category,
  Set<int> levels = const {},
  int limit = 10,
}) async {
  final all = <ArticleSummary>[];
  FeedCursor? after;
  while (true) {
    final page = await repo.page(
      category: category,
      levels: levels,
      after: after,
      limit: limit,
    );
    all.addAll(page);
    if (page.length < limit) return all;
    after = page.last.cursor;
  }
}

void main() {
  test('keyset pages cover every article once, newest first', () async {
    final repo = await _seededRepo();
    final all = await _readAll(repo, limit: 7);

    expect(all, hasLength(24));
    expect(all.map((a) => a.id).toSet(), hasLength(24));
    for (var i = 1; i < all.length; i++) {
      final prev = all[i - 1], cur = all[i];
      final ordered =
          prev.publishedAt > cur.publishedAt ||
          (prev.publishedAt == cur.publishedAt &&
              prev.id.compareTo(cur.id) > 0);
      expect(ordered, isTrue, reason: '${prev.id} before ${cur.id}');
    }
  });

  test('category and level filters combine', () async {
    final repo = await _seededRepo();

    final tech = await _readAll(repo, category: 'tech');
    expect(tech, hasLength(6));
    expect(tech.every((a) => a.category == 'tech'), isTrue);

    final easyOrHard = await _readAll(repo, levels: {1, 3});
    expect(easyOrHard, hasLength(16));
    expect(easyOrHard.every((a) => a.level != 2), isTrue);

    final techL2 = await _readAll(repo, category: 'tech', levels: {2});
    expect(techL2.map((a) => a.id), unorderedEquals(['tech-2-a', 'tech-2-b']));
  });

  test(
    'articles inserted at the top do not shift pages already read',
    () async {
      final repo = await _seededRepo();
      final first = await repo.page(limit: 5);

      await repo.upsertAll([
        _remoteArticle('remote-x', publishedAt: first.first.publishedAt + 1),
      ]);

      final next = await repo.page(after: first.last.cursor, limit: 5);
      expect(
        next
            .map((a) => a.id)
            .toSet()
            .intersection(first.map((a) => a.id).toSet()),
        isEmpty,
      );
      expect(next.any((a) => a.id == 'remote-x'), isFalse);
    },
  );

  test('upsertAll is idempotent', () async {
    final repo = await _seededRepo();
    final a = _remoteArticle('remote-x', publishedAt: 1);
    await repo.upsertAll([a]);
    await repo.upsertAll([a]);
    expect(await _readAll(repo), hasLength(25));
    expect(await repo.paragraphs('remote-x'), ['One.', 'Two.']);
  });

  test('reads wait for the seed import to finish', () async {
    final db = await openTestDb();
    final ready = Completer<void>();
    final repo = ArticleRepository(db, ready: ready.future);

    var done = false;
    final pending = repo.page().then((_) => done = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(done, isFalse);

    ready.complete();
    await pending;
    expect(done, isTrue);
  });

  group('MockArticleRemote', () {
    test('serves unseen pool articles two at a time, then nothing', () async {
      final repo = await _seededRepo();
      final pool = File('assets/seed/remote_pool.json').readAsStringSync();
      final remote = MockArticleRemote(
        loadPool: () async => pool,
        latency: Duration.zero,
        clock: () => _now,
      );

      final first = await remote.fetchLatest(repo.knownIds);
      expect(first, hasLength(2));
      expect(first.first['published_at'], _now);
      await repo.upsertAll(first);

      final second = await remote.fetchLatest(repo.knownIds);
      expect(second, hasLength(2));
      expect(
        second
            .map((a) => a['id'])
            .toSet()
            .intersection(first.map((a) => a['id']).toSet()),
        isEmpty,
      );
      await repo.upsertAll(second);

      expect(await remote.fetchLatest(repo.knownIds), isEmpty);
      // Newly served articles sort to the top of the feed.
      final top = await repo.page(limit: 4);
      expect(top.every((a) => a.id.startsWith('remote-')), isTrue);
    });
  });
}

Map<String, Object?> _remoteArticle(String id, {required int publishedAt}) => {
  'id': id,
  'title': 'T',
  'summary': 'S',
  'cover': 'g1',
  'category': 'daily',
  'level': 2,
  'word_count': 2,
  'published_at': publishedAt,
  'paragraphs': jsonDecode('["One.", "Two."]'),
};

/// Later than every seed article (2026-08..10), as "now" would be.
final _now = DateTime.utc(2026, 11, 1).millisecondsSinceEpoch;
