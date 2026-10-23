import 'package:flutter_test/flutter_test.dart';
import 'package:glean/features/reader/application/reading_session.dart';
import 'package:glean/features/reader/data/progress_repository.dart';
import 'package:glean/features/reader/data/reading_time_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_db.dart';

/// Manual clock: tests move time explicitly.
class _Clock {
  int now = 1000000;

  int call() => now;

  void advance(Duration d) => now += d.inMilliseconds;
}

const _user = 'u1';
const _article = 'tech-1-a';

ReadingPosition _at(double progress) => ReadingPosition(
  scrollOffset: progress * 1000,
  anchorPara: 0,
  anchorDelta: 0,
  fontScale: 1,
  progress: progress,
);

class _Harness {
  _Harness(this.db, this.clock, {int words = 2000, int prior = 0})
    : progress = ProgressRepository(db, clock: clock.call),
      time = ReadingTimeRepository(db, clock: clock.call) {
    var n = 0;
    session = ReadingSession(
      userId: _user,
      articleId: _article,
      wordCount: words,
      sessionId: 's1',
      progress: progress,
      time: time,
      priorActiveMs: prior,
      alreadyFinished: false,
      clock: clock.call,
      newId: () => 'seg-${n++}',
      onFinished: () => finishedEvents++,
    );
  }

  final Database db;
  final _Clock clock;
  final ProgressRepository progress;
  final ReadingTimeRepository time;
  late final ReadingSession session;
  int finishedEvents = 0;

  /// Ticks every 250 ms for [d], like the reader does.
  Future<void> read(Duration d, {bool interact = true}) async {
    for (var t = 0; t < d.inMilliseconds; t += 250) {
      clock.advance(const Duration(milliseconds: 250));
      if (interact) session.onInteraction();
      await session.tick();
    }
  }

  Future<double?> storedOffset() async =>
      (await progress.get(_user, _article))?.position.scrollOffset;

  Future<int> storedMs() => time.totalActiveMs(_user, _article);
}

Future<_Harness> _harness({int words = 2000, int prior = 0}) async {
  final db = await openTestDb();
  await insertArticle(db, _article);
  return _Harness(db, _Clock(), words: words, prior: prior);
}

void main() {
  group('position saving', () {
    test(
      'first position is saved at once, then at most once a second',
      () async {
        final h = await _harness();
        await h.session.onPosition(_at(0.1));
        expect(await h.storedOffset(), 100);

        h.clock.advance(const Duration(milliseconds: 300));
        await h.session.onPosition(_at(0.2));
        expect(await h.storedOffset(), 100, reason: 'throttled');

        h.clock.advance(const Duration(milliseconds: 800));
        await h.session.onPosition(_at(0.3));
        expect(await h.storedOffset(), 300, reason: '1 s since last save');
      },
    );

    test('a pending position is saved 500 ms after scrolling stops', () async {
      final h = await _harness();
      await h.session.onPosition(_at(0.1));
      h.clock.advance(const Duration(milliseconds: 100));
      await h.session.onPosition(_at(0.4));

      await h.read(const Duration(milliseconds: 250));
      expect(await h.storedOffset(), 100);
      await h.read(const Duration(milliseconds: 500));
      expect(await h.storedOffset(), 400);
    });

    test('flush writes the pending position immediately', () async {
      final h = await _harness();
      await h.session.onPosition(_at(0.1));
      h.clock.advance(const Duration(milliseconds: 10));
      await h.session.onPosition(_at(0.7));
      await h.session.flush();
      expect(await h.storedOffset(), 700);
    });
  });

  group('reading time', () {
    test(
      'accrues while active and interacting, saved as one segment',
      () async {
        final h = await _harness();
        await h.read(const Duration(seconds: 12));
        await h.session.flush();
        expect(await h.storedMs(), closeTo(12000, 300));
        expect(h.session.activeMs, closeTo(12000, 300));
      },
    );

    test('stops after the idle limit without interaction', () async {
      final h = await _harness();
      h.session.onInteraction();
      await h.read(const Duration(seconds: 150), interact: false);
      await h.session.flush();
      expect(
        await h.storedMs(),
        closeTo(ReadingSession.idleLimit.inMilliseconds, 300),
      );
    });

    test(
      'nothing accrues while inactive; resuming starts a new segment',
      () async {
        final h = await _harness();
        await h.read(const Duration(seconds: 5));
        await h.session.setActive(false);
        await h.read(const Duration(seconds: 20));
        await h.session.setActive(true);
        await h.read(const Duration(seconds: 5));
        await h.session.flush();

        expect(await h.storedMs(), closeTo(10000, 600));
        final segments = await h.db.query('reading_segments');
        expect(segments, hasLength(2));
      },
    );

    test('segments under 3 s are dropped', () async {
      final h = await _harness();
      await h.read(const Duration(seconds: 2));
      await h.session.flush();
      expect(await h.storedMs(), 0);
    });
  });

  group('finishing', () {
    test('needs 90 % seen and enough time; fires exactly once', () async {
      // 100 words -> 15 s minimum at 400 wpm.
      final h = await _harness(words: 100);
      expect(h.session.finishMinTime, const Duration(seconds: 15));

      await h.session.onPosition(_at(0.95));
      await h.read(const Duration(seconds: 10));
      expect(h.finishedEvents, 0, reason: 'too fast to have read it');

      await h.read(const Duration(seconds: 6));
      expect(h.finishedEvents, 1);
      await h.read(const Duration(seconds: 5));
      expect(h.finishedEvents, 1);

      final p = await h.progress.get(_user, _article);
      expect(p!.status, ReadingStatus.finished);
    });

    test('long articles cap the required time at 30 s', () async {
      final h = await _harness(words: 5000);
      expect(h.session.finishMinTime, const Duration(seconds: 30));
    });

    test('time from earlier visits counts', () async {
      final h = await _harness(words: 100, prior: 20000);
      await h.session.onPosition(_at(0.92));
      expect(h.finishedEvents, 1);
    });

    test('not finished below 90 % no matter how long', () async {
      final h = await _harness(words: 100);
      await h.session.onPosition(_at(0.85));
      await h.read(const Duration(seconds: 60));
      expect(h.finishedEvents, 0);
    });
  });
}
