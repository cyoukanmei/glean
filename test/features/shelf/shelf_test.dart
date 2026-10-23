import 'package:flutter_test/flutter_test.dart';
import 'package:glean/features/library/data/marks_repository.dart';
import 'package:glean/features/reader/data/progress_repository.dart';
import 'package:glean/features/shelf/application/shelf.dart';

import '../../helpers/test_db.dart';

const _user = 'u1';

ReadingPosition _at(double progress) => ReadingPosition(
  scrollOffset: 0,
  anchorPara: 0,
  anchorDelta: 0,
  fontScale: 1,
  progress: progress,
);

void main() {
  test('the shelf merges history and marks, most recent activity first, '
      'and each filter picks its books', () async {
    final db = await openTestDb();
    for (final id in ['read', 'done', 'starred', 'later', 'other']) {
      await insertArticle(db, id);
    }
    // One clock for both repositories, so their timestamps interleave.
    final clock = FakeClock();
    final progress = ProgressRepository(db, clock: clock.call);
    final marks = MarksRepository(db, clock: clock.call);

    await progress.save(_user, 'done', _at(1));
    await progress.markFinished(_user, 'done');
    await marks.set(_user, 'later', MarkKind.later, on: true);
    await progress.save(_user, 'read', _at(0.4));
    await marks.set(_user, 'starred', MarkKind.favorite, on: true);
    // Starring a book read earlier moves it up.
    await marks.set(_user, 'done', MarkKind.favorite, on: true);
    await progress.save('someone-else', 'other', _at(0.5));

    final shelf = await loadShelf(
      userId: _user,
      progress: progress,
      marks: marks,
    );
    expect(shelf.map((e) => e.article.id), [
      'done',
      'starred',
      'read',
      'later',
    ]);

    List<String> pick(ShelfFilter f) => [
      for (final e in shelf)
        if (e.matches(f)) e.article.id,
    ];
    expect(pick(ShelfFilter.reading), ['read']);
    expect(pick(ShelfFilter.favorite), ['done', 'starred']);
    expect(pick(ShelfFilter.later), ['later']);
    expect(pick(ShelfFilter.finished), ['done']);
    expect(shelf.first.progress, 1);
  });
}
