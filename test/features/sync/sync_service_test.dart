import 'package:flutter_test/flutter_test.dart';
import 'package:glean/features/library/data/marks_repository.dart';
import 'package:glean/features/reader/data/progress_repository.dart';
import 'package:glean/features/sync/data/mock_sync_server.dart';
import 'package:glean/features/sync/sync_service.dart';
import 'package:glean/features/vocab/data/vocab_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_db.dart';

/// One clock for every device and the server, so "later" is well defined.
class _Time {
  int now = 1000;
  int call() => now += 10;
}

class _Device {
  _Device(this.db, this.sync, this.progress, this.vocab, this.remoteChanges);

  final Database db;
  final SyncService sync;
  final ProgressRepository progress;
  final VocabRepository vocab;
  final List<int> remoteChanges;
}

const _user = 'u1';

ReadingPosition _at(double progress) => ReadingPosition(
  scrollOffset: progress * 1000,
  anchorPara: (progress * 10).floor(),
  anchorDelta: 0,
  fontScale: 1,
  progress: progress,
);

const _source = WordSource(
  articleId: 'a1',
  paraIndex: 0,
  charStart: 0,
  charEnd: 5,
  sentence: 'Hello there.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Time time;
  late MockSyncServer server;
  var online = true;
  var user = _user;

  setUp(() async {
    time = _Time();
    online = true;
    user = _user;
    sqfliteFfiInit();
    final serverDb = await MockSyncServer.open(
      databaseFactoryFfi,
      '${await newTestDbPath()}.server',
    );
    addTearDown(serverDb.close);
    server = MockSyncServer(
      serverDb,
      isOnline: () => online,
      clock: time.call,
      latency: Duration.zero,
    );
  });

  Future<_Device> device(String id) async {
    final db = await openTestDb();
    await insertArticle(db, 'a1');
    final changes = <int>[];
    final sync = SyncService(
      db: db,
      server: server,
      deviceId: id,
      userId: () => user,
      isOnline: () => online,
      onRemoteChanges: () => changes.add(1),
      clock: time.call,
    );
    addTearDown(sync.dispose);
    return _Device(
      db,
      sync,
      ProgressRepository(db, clock: time.call),
      VocabRepository(db, clock: time.call),
      changes,
    );
  }

  Future<Map<String, Object?>> word(_Device d) async =>
      (await d.db.query('vocab')).single;

  test('changes on one device reach the other', () async {
    final phone = await device('phone');
    final tablet = await device('tablet');
    await phone.progress.save(_user, 'a1', _at(0.4));
    await phone.vocab.collect(
      userId: _user,
      word: 'hello',
      lemma: 'hello',
      definition: 'int. 你好',
      source: _source,
    );

    final up = await phone.sync.sync();
    expect(up.pushed, 2);
    expect(await phone.sync.pending(), (0, 0));
    expect((await word(phone))['version'], 1);

    final down = await tablet.sync.sync();
    expect(down.pulled, 2);
    expect(tablet.remoteChanges, [1]);
    expect(await tablet.vocab.isCollected(_user, 'hello'), isTrue);
    expect((await tablet.progress.get(_user, 'a1'))!.maxProgress, 0.4);
    expect(await tablet.sync.pending(), (
      0,
      0,
    ), reason: 'pulled rows are clean');

    // Nothing new: a second sync moves nothing.
    final again = await tablet.sync.sync();
    expect((again.pushed, again.pulled), (0, 0));
  });

  test('word list: the later write wins, a delete included', () async {
    final phone = await device('phone');
    final tablet = await device('tablet');
    await phone.vocab.collect(
      userId: _user,
      word: 'hello',
      lemma: 'hello',
      definition: 'int. 你好',
      source: _source,
    );
    await phone.sync.sync();
    await tablet.sync.sync();

    // Offline on both: the phone deletes, then the tablet marks it known.
    final id = (await word(phone))['id']! as String;
    await phone.vocab.delete(id);
    await tablet.db.update('vocab', {
      'status': 2,
      'dirty': 1,
      'updated_at': time(),
    });

    final phoneUp = await phone.sync.sync();
    expect(phoneUp.conflicts, isEmpty);
    final tabletUp = await tablet.sync.sync();
    expect(tabletUp.conflicts, hasLength(1), reason: 'based on version 1');
    await phone.sync.sync();

    for (final d in [phone, tablet]) {
      final w = await word(d);
      expect(w['deleted_at'], isNull, reason: 'the later edit revived it');
      expect(w['status'], 2);
      expect(w['dirty'], 0);
    }
  });

  test('reading progress merges: furthest progress, latest position', () async {
    final phone = await device('phone');
    final tablet = await device('tablet');
    await phone.progress.save(_user, 'a1', _at(0.8));
    await phone.sync.sync();
    await tablet.progress.save(_user, 'a1', _at(0.3)); // read later
    await tablet.sync.sync();
    await phone.sync.sync();

    for (final d in [phone, tablet]) {
      final p = (await d.progress.get(_user, 'a1'))!;
      expect(p.maxProgress, 0.8);
      expect(p.position.progress, 0.3);
      expect(p.position.scrollOffset, 300);
    }
  });

  test('a finish on one device is never undone by another', () async {
    final phone = await device('phone');
    final tablet = await device('tablet');
    await phone.progress.save(_user, 'a1', _at(0.95));
    await phone.progress.markFinished(_user, 'a1');
    await tablet.progress.save(_user, 'a1', _at(0.1));
    await phone.sync.sync();
    await tablet.sync.sync();
    final p = (await tablet.progress.get(_user, 'a1'))!;
    expect(p.status, ReadingStatus.finished);
    expect(p.maxProgress, 1.0);
  });

  test('offline and guest syncs are skipped; dirty rows wait', () async {
    final phone = await device('phone');
    await phone.progress.save(_user, 'a1', _at(0.2));
    online = false;
    expect((await phone.sync.sync()).skipped, 'offline');
    expect(await phone.sync.pending(), (1, 0));

    online = true;
    user = 'guest';
    expect((await phone.sync.sync()).skipped, 'guest');

    user = _user;
    expect((await phone.sync.sync()).pushed, 1);
  });

  test('the simulated second device shows up on the next pull', () async {
    final phone = await device('phone');
    await phone.vocab.collect(
      userId: _user,
      word: 'hello',
      lemma: 'hello',
      definition: 'int. 你好',
      source: _source,
    );
    await phone.progress.save(_user, 'a1', _at(0.2));
    await phone.sync.sync();

    final changed = await server.simulateOtherDevice(_user);
    expect(changed, hasLength(2));
    final r = await phone.sync.sync();
    expect(r.pulled, 2);
    expect((await word(phone))['status'], 2);
    expect(
      (await phone.progress.get(_user, 'a1'))!.position.progress,
      closeTo(0.4, 1e-9),
    );
  });

  test('收藏 syncs like the word list, unmarking included', () async {
    final phone = await device('phone');
    final tablet = await device('tablet');
    final phoneMarks = MarksRepository(phone.db, clock: time.call);
    await phoneMarks.set(_user, 'a1', MarkKind.favorite, on: true);
    await phone.sync.sync();
    await tablet.sync.sync();
    final tabletMarks = MarksRepository(tablet.db, clock: time.call);
    expect(await tabletMarks.of(_user, 'a1'), {MarkKind.favorite});

    await tabletMarks.set(_user, 'a1', MarkKind.favorite, on: false);
    await tablet.sync.sync();
    await phone.sync.sync();
    expect(await phoneMarks.of(_user, 'a1'), isEmpty);
    expect(await phone.sync.pending(), (0, 0));
  });
}
