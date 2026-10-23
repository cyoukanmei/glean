import 'package:glean/features/vocab/data/vocab_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_db.dart';

const _user = 'u1';

WordSource _from(String articleId, {int para = 0}) => WordSource(
  articleId: articleId,
  paraIndex: para,
  charStart: 10,
  charEnd: 16,
  sentence: 'They bought a new phone.',
);

Future<void> _collect(
  VocabRepository repo, {
  String article = 'tech-1-a',
  int para = 0,
}) => repo.collect(
  userId: _user,
  word: 'bought',
  lemma: 'buy',
  definition: 'vt. 买',
  source: _from(article, para: para),
);

void main() {
  test(
    'collecting the same word twice keeps one row and the first source',
    () async {
      final db = await openTestDb();
      final repo = VocabRepository(db, clock: FakeClock().call);

      await _collect(repo, article: 'tech-1-a');
      await _collect(repo, article: 'daily-2-b', para: 3);

      final items = await repo.list(_user);
      expect(items, hasLength(1));
      expect(items.single.source.articleId, 'tech-1-a');
      expect(await db.query('vocab'), hasLength(1));
    },
  );

  test('delete hides the word; re-collecting revives the same row', () async {
    final db = await openTestDb();
    final repo = VocabRepository(db, clock: FakeClock().call);

    await _collect(repo, article: 'tech-1-a');
    final id = (await repo.list(_user)).single.id;

    await repo.delete(id);
    expect(await repo.list(_user), isEmpty);
    expect(await repo.isCollected(_user, 'buy'), isFalse);

    await _collect(repo, article: 'culture-3-a', para: 2);
    final revived = (await repo.list(_user)).single;
    expect(revived.id, id);
    expect(revived.source.articleId, 'culture-3-a');
    expect(revived.source.paraIndex, 2);
    expect(await db.query('vocab'), hasLength(1));
  });

  test('restore undoes a delete and keeps the original source', () async {
    final db = await openTestDb();
    final repo = VocabRepository(db, clock: FakeClock().call);
    await _collect(repo, article: 'tech-1-a');
    final id = (await repo.list(_user)).single.id;

    await repo.delete(id);
    await repo.restore(id);

    final item = (await repo.list(_user)).single;
    expect(item.id, id);
    expect(item.source.articleId, 'tech-1-a');
  });

  test('words are scoped per user', () async {
    final db = await openTestDb();
    final repo = VocabRepository(db, clock: FakeClock().call);
    await _collect(repo);
    await repo.collect(
      userId: 'u2',
      word: 'buys',
      lemma: 'buy',
      definition: 'vt. 买',
      source: _from('tech-1-a'),
    );

    expect(await repo.list(_user), hasLength(1));
    expect(await repo.list('u2'), hasLength(1));
  });

  test('counts live words saved from one article', () async {
    final db = await openTestDb();
    final repo = VocabRepository(db, clock: FakeClock().call);
    await _collect(repo, article: 'tech-1-a');
    await repo.collect(
      userId: _user,
      word: 'phone',
      lemma: 'phone',
      definition: 'n. 电话',
      source: _from('tech-1-a'),
    );
    await repo.collect(
      userId: _user,
      word: 'new',
      lemma: 'new',
      definition: 'adj. 新的',
      source: _from('daily-2-b'),
    );
    expect(await repo.countFromArticle(_user, 'tech-1-a'), 2);

    await repo.delete((await repo.find(_user, 'buy'))!.id);
    expect(await repo.countFromArticle(_user, 'tech-1-a'), 1);
    expect(await repo.countFromArticle('someone-else', 'tech-1-a'), 0);
  });

  test('setStatus records the review and marks the word for sync', () async {
    final db = await openTestDb();
    final repo = VocabRepository(db, clock: FakeClock().call);
    await _collect(repo);
    final item = (await repo.list(_user)).single;
    await db.update('vocab', {'dirty': 0});

    await repo.setStatus(item.id, VocabStatus.mastered);
    final row = (await db.query('vocab')).single;
    expect(row['status'], VocabStatus.mastered);
    expect(row['dirty'], 1);
    expect(row['updated_at'], greaterThan(item.createdAt));

    await db.update('vocab', {'dirty': 0});
    await repo.setStatus(item.id, VocabStatus.mastered);
    expect((await db.query('vocab')).single['dirty'], 0, reason: 'no-op');
  });
}
