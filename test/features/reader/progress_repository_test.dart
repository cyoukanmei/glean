import 'package:english_reader/features/reader/data/progress_repository.dart';
import 'package:english_reader/features/reader/data/reading_time_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_db.dart';

const _user = 'u1';
const _article = 'tech-1-a';

ReadingPosition _at(double progress, {double offset = 0}) => ReadingPosition(
  scrollOffset: offset,
  anchorPara: 2,
  anchorDelta: 0.5,
  fontScale: 1,
  progress: progress,
);

void main() {
  group('ProgressRepository', () {
    test('saving the same position twice leaves one identical row', () async {
      final db = await openTestDb();
      await insertArticle(db, _article);
      final repo = ProgressRepository(db, clock: FakeClock().call);

      await repo.save(_user, _article, _at(0.4, offset: 812));
      await repo.save(_user, _article, _at(0.4, offset: 812));

      final rows = await db.query('reading_progress');
      expect(rows, hasLength(1));
      final p = await repo.get(_user, _article);
      expect(p!.position.scrollOffset, 812);
      expect(p.status, ReadingStatus.reading);
    });

    test(
      'position follows the reader back up, max_progress never drops',
      () async {
        final db = await openTestDb();
        await insertArticle(db, _article);
        final repo = ProgressRepository(db, clock: FakeClock().call);

        await repo.save(_user, _article, _at(0.8, offset: 1600));
        await repo.save(_user, _article, _at(0.3, offset: 600));

        final p = await repo.get(_user, _article);
        expect(p!.position.scrollOffset, 600);
        expect(p.position.progress, 0.3);
        expect(p.maxProgress, 0.8);
      },
    );

    test('a write stamped older than the stored row is ignored', () async {
      final db = await openTestDb();
      await insertArticle(db, _article);
      final clock = FakeClock(5000);
      final repo = ProgressRepository(db, clock: clock.call);

      await repo.save(_user, _article, _at(0.6, offset: 1200));
      clock.now = 10; // e.g. a stale flush racing a newer one
      await repo.save(_user, _article, _at(0.1, offset: 100));

      final p = await repo.get(_user, _article);
      expect(p!.position.scrollOffset, 1200);
    });

    test(
      'markFinished is true exactly once and status never goes back',
      () async {
        final db = await openTestDb();
        await insertArticle(db, _article);
        final repo = ProgressRepository(db, clock: FakeClock().call);
        await repo.save(_user, _article, _at(0.95));

        expect(await repo.markFinished(_user, _article), isTrue);
        expect(await repo.markFinished(_user, _article), isFalse);

        await repo.save(_user, _article, _at(0.2));
        final p = await repo.get(_user, _article);
        expect(p!.status, ReadingStatus.finished);
        expect(p.finishedAt, isNotNull);
        expect(p.maxProgress, 1.0);
      },
    );

    test('position survives closing and reopening the database', () async {
      final path = await newTestDbPath();
      final first = await openTestDb(path: path);
      await insertArticle(first, _article);
      await ProgressRepository(
        first,
      ).save(_user, _article, _at(0.5, offset: 999));
      await first.close();

      final reopened = await openTestDb(path: path);
      final p = await ProgressRepository(reopened).get(_user, _article);
      expect(p!.position.scrollOffset, 999);
    });
  });

  group('ReadingTimeRepository', () {
    test('rewriting a segment total never double-counts', () async {
      final db = await openTestDb();
      final repo = ReadingTimeRepository(db, clock: FakeClock().call);

      Future<void> write(String id, int ms) => repo.saveSegment(
        segmentId: id,
        userId: _user,
        articleId: _article,
        sessionId: 's1',
        startedAt: 0,
        activeMs: ms,
      );

      await write('seg-a', 5000);
      await write('seg-a', 10000);
      await write('seg-a', 10000); // replayed write
      await write('seg-a', 7000); // out-of-order older total
      await write('seg-b', 3000);

      expect(await repo.totalActiveMs(_user, _article), 13000);
    });
  });
}
