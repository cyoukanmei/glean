import 'package:flutter_test/flutter_test.dart';
import 'package:glean/features/auth/data/auth_repository.dart';
import 'package:glean/features/reader/data/progress_repository.dart';
import 'package:glean/features/vocab/data/vocab_repository.dart';

import '../../helpers/test_db.dart';

void main() {
  test(
    'register then log in; the password is stored salted and hashed',
    () async {
      final db = await openTestDb();
      final repo = AuthRepository(db, clock: FakeClock().call);

      await repo.register('mei', 'secret1');
      final row = (await db.query('users')).single;
      expect(row['password_hash'], isNot(contains('secret1')));
      expect((row['salt']! as String).length, 32);

      final (user, token) = await repo.login('mei', 'secret1');
      expect(user.username, 'mei');
      expect((await repo.userForToken(token))?.id, user.id);
    },
  );

  test('wrong password, unknown user and duplicates are refused', () async {
    final db = await openTestDb();
    final repo = AuthRepository(db, clock: FakeClock().call);
    await repo.register('mei', 'secret1');

    expect(() => repo.login('mei', 'nope123'), throwsA(isA<AuthException>()));
    expect(() => repo.login('nobody', 'x'), throwsA(isA<AuthException>()));
    expect(
      () => repo.register('MEI', 'another1'),
      throwsA(isA<AuthException>()),
      reason: 'usernames are case-insensitive',
    );
    expect(() => repo.register('a', 'secret1'), throwsA(isA<AuthException>()));
    expect(
      () => repo.register('ok_name', '123'),
      throwsA(isA<AuthException>()),
    );
  });

  test('sessions expire after 7 days and logout ends them', () async {
    final db = await openTestDb();
    final clock = FakeClock();
    final repo = AuthRepository(db, clock: clock.call);
    await repo.ensureDemoUser();
    await repo.ensureDemoUser(); // idempotent

    final (_, token) = await repo.login('demo', 'glean123');
    clock.now += AuthRepository.sessionTtl.inMilliseconds - 10;
    expect(await repo.userForToken(token), isNotNull);
    clock.now += 20;
    expect(await repo.userForToken(token), isNull);
    expect(await db.query('sessions'), isEmpty, reason: 'expired row removed');

    final (_, second) = await repo.login('demo', 'glean123');
    await repo.logout(second);
    expect(await repo.userForToken(second), isNull);
    expect(await repo.userForToken('made-up'), isNull);
  });

  test('the first login takes over what was read as a guest', () async {
    final db = await openTestDb();
    final clock = FakeClock();
    await insertArticle(db, 'a1');
    await ProgressRepository(db, clock: clock.call).save(
      AuthRepository.guestId,
      'a1',
      const ReadingPosition(
        scrollOffset: 10,
        anchorPara: 0,
        anchorDelta: 0,
        fontScale: 1,
        progress: 0.4,
      ),
    );
    await VocabRepository(db, clock: clock.call).collect(
      userId: AuthRepository.guestId,
      word: 'hello',
      lemma: 'hello',
      definition: 'int. 你好',
      source: const WordSource(
        articleId: 'a1',
        paraIndex: 0,
        charStart: 0,
        charEnd: 5,
      ),
    );

    final repo = AuthRepository(db, clock: clock.call);
    await repo.ensureDemoUser();
    final (user, _) = await repo.login('demo', 'glean123');

    expect(await ProgressRepository(db).get(user.id, 'a1'), isNotNull);
    expect(await VocabRepository(db).isCollected(user.id, 'hello'), isTrue);
    expect(
      await VocabRepository(db).isCollected(AuthRepository.guestId, 'hello'),
      isFalse,
    );
  });
}
