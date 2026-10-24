import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glean/features/articles/data/article_remote.dart';
import 'package:glean/features/articles/data/article_repository.dart';
import 'package:glean/features/sync/background/background_job.dart';
import 'package:glean/features/sync/sync_service.dart';

import '../../helpers/test_db.dart';

void main() {
  late ArticleRepository repo;
  late MockArticleRemote remote;
  late List<List<String>> notified;

  setUp(() async {
    final db = await openTestDb();
    repo = ArticleRepository(db);
    final pool = File('assets/seed/remote_pool.json').readAsStringSync();
    remote = MockArticleRemote(
      loadPool: () async => pool,
      latency: Duration.zero,
    );
    notified = [];
  });

  BackgroundJob job({Future<SyncResult> Function()? sync}) => BackgroundJob(
    articles: repo,
    remote: remote,
    notify: (titles) async => notified.add(titles),
    sync: sync,
  );

  test('stores new articles, announces them once, then stays quiet', () async {
    var syncs = 0;
    final first = await job(sync: () async => SyncResult(at: ++syncs)).run();
    expect(first.newTitles, hasLength(2));
    expect(notified, [first.newTitles]);
    expect(syncs, 1);
    // They are in the local database, so the app shows them offline too.
    final stored = await repo.page(limit: 2);
    expect(stored.map((a) => a.title), unorderedEquals(first.newTitles));

    await job().run();
    final third = await job().run();
    expect(third.newTitles, isEmpty);
    expect(notified, hasLength(2), reason: 'nothing new, no notification');
  });

  test('a guest (no sync) still gets new articles', () async {
    final run = await job().run();
    expect(run.sync, isNull);
    expect(run.newTitles, isNotEmpty);
  });
}
