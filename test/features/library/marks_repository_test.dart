import 'package:flutter_test/flutter_test.dart';
import 'package:glean/features/library/data/marks_repository.dart';
import 'package:glean/features/reader/data/progress_repository.dart';

import '../../helpers/test_db.dart';

const _user = 'u1';

const _pos = ReadingPosition(
  scrollOffset: 0,
  anchorPara: 0,
  anchorDelta: 0,
  fontScale: 1,
  progress: 0.4,
);

void main() {
  test('marks list newest first, removal keeps a tombstone, re-marking '
      'revives it', () async {
    final db = await openTestDb();
    for (final id in ['a1', 'a2']) {
      await insertArticle(db, id);
    }
    final clock = FakeClock();
    final repo = MarksRepository(db, clock: clock.call);

    await repo.set(_user, 'a1', MarkKind.favorite, on: true);
    await repo.set(_user, 'a2', MarkKind.favorite, on: true);
    await repo.set(_user, 'a2', MarkKind.later, on: true);
    await repo.set(_user, 'a1', MarkKind.favorite, on: true); // no-op

    final favs = await repo.list(_user, MarkKind.favorite);
    expect(favs.map((f) => f.$1.id), ['a2', 'a1']);
    expect(await repo.of(_user, 'a2'), {MarkKind.favorite, MarkKind.later});
    expect(await repo.counts(_user), {MarkKind.favorite: 2, MarkKind.later: 1});

    await repo.set(_user, 'a1', MarkKind.favorite, on: false);
    expect(await repo.of(_user, 'a1'), isEmpty);
    expect(
      (await db.query(
        'article_marks',
        where: "article_id = 'a1'",
      )).single['deleted_at'],
      isNotNull,
      reason: 'tombstone for sync',
    );

    await repo.set(_user, 'a1', MarkKind.favorite, on: true);
    expect(
      (await repo.list(_user, MarkKind.favorite)).first.$1.id,
      'a1',
      reason: 'revived as the newest',
    );
    expect(await db.query('article_marks'), hasLength(3));
  });

  test('history lists every opened article, most recent first', () async {
    final db = await openTestDb();
    for (final id in ['a1', 'a2', 'a3']) {
      await insertArticle(db, id);
    }
    final progress = ProgressRepository(db, clock: FakeClock().call);
    await progress.save(_user, 'a2', _pos);
    await progress.save(_user, 'a1', _pos);
    await progress.save(_user, 'a3', _pos);
    await progress.save(_user, 'a1', _pos); // read again

    final history = await progress.history(_user);
    expect(history.map((h) => h.$1.id), ['a1', 'a3', 'a2']);
    expect(history.first.$2.maxProgress, 0.4);
    expect(await progress.history('someone-else'), isEmpty);
  });
}
