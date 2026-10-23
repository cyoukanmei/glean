import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:glean/core/analytics/analytics_service.dart';
import 'package:glean/core/analytics/collector.dart';
import 'package:glean/core/analytics/event_queue.dart';
import 'package:glean/core/analytics/event_spec.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_db.dart';

class _Clock {
  int now = 1000000;
  int call() => now;
}

Future<(AnalyticsService, Database, _Clock, MockCollector, List<bool>)>
_setUp() async {
  final db = await openTestDb();
  final clock = _Clock();
  final online = [true];
  final collector = MockCollector(
    db,
    isOnline: () => online.first,
    clock: clock.call,
    latency: Duration.zero,
  );
  final service = AnalyticsService(
    queue: EventQueue(db, clock: clock.call, random: Random(1)),
    collector: collector,
    deviceId: 'device-1',
    appVersion: '1.0.0+1',
    platform: 'android',
    userId: () => 'u1',
    isOnline: () => online.first,
    clock: clock.call,
    batchSize: 3,
  );
  addTearDown(service.dispose);
  return (service, db, clock, collector, online);
}

Future<int> _count(Database db, String table, [String? where]) async =>
    (await db.rawQuery(
          'SELECT COUNT(*) AS n FROM $table${where == null ? '' : ' WHERE $where'}',
        )).single['n']!
        as int;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'events are queued with common params and uploaded in batches',
    () async {
      final (service, db, _, _, _) = await _setUp();
      for (var i = 0; i < 7; i++) {
        service.track('page_view', {'page': 'home'});
      }
      final result = await service.flush();

      expect(result.sent, 7);
      expect(await _count(db, 'collected_events'), 7);
      expect(await _count(db, 'upload_log'), 3, reason: 'batches of 3, 3, 1');
      final row = (await db.query('collected_events', orderBy: 'ts')).first;
      final params = jsonDecode(row['params']! as String) as Map;
      expect(params, containsPair('device_id', 'device-1'));
      expect(params, containsPair('platform', 'android'));
      expect(params, containsPair('network', 'online'));
      expect(row['user_id'], 'u1');
      expect(row['session_id'], service.sessionId);
    },
  );

  test('offline: nothing is sent, events wait and go once online', () async {
    final (service, db, _, _, online) = await _setUp();
    online.first = false;
    service.track('article_open', {'article_id': 'a1', 'surface': 'all'});
    expect((await service.flush()).skipped, 'offline');
    expect(await _count(db, 'event_queue', 'status = 0'), 1);

    online.first = true;
    service.onConnectivityChanged(true);
    await service.flush();
    expect(await _count(db, 'collected_events'), 1);
    expect(await _count(db, 'event_queue', 'status = 2'), 1);
  });

  test('a failed upload backs off exponentially, then succeeds', () async {
    final (service, db, clock, collector, _) = await _setUp();
    collector.failUploads = true;
    service.track('page_view', {'page': 'me'});
    expect((await service.flush()).failed, 1);

    final row = (await db.query('event_queue')).single;
    expect(row['attempts'], 1);
    final wait = (row['next_attempt_at']! as int) - clock.now;
    expect(wait, inInclusiveRange(4000, 6000), reason: '5 s ± 20 %');

    collector.failUploads = false;
    expect((await service.flush()).sent, 0, reason: 'not due yet');
    clock.now += 6000;
    expect((await service.flush()).sent, 1);
    expect(
      (await db.query(
        'upload_log',
        orderBy: 'sent_at',
      )).map((r) => r['http_status']),
      [503, 200],
    );
  });

  test('after the last attempt an event is parked as dead', () async {
    final (service, db, clock, collector, _) = await _setUp();
    collector.failUploads = true;
    service.track('page_view', {'page': 'me'});
    for (var i = 0; i < EventQueue.maxAttempts; i++) {
      await service.flush();
      clock.now += EventQueue.maxBackoff.inMilliseconds * 2;
    }
    expect((await db.query('event_queue')).single['status'], EventStatus.dead);
  });

  test('a batch stuck in "sending" after a kill is re-sent once, deduped by '
      'event_id on the server', () async {
    final (service, db, clock, collector, _) = await _setUp();
    service.track('page_view', {'page': 'home'});
    await service.flush();
    // Simulate: the server got the batch but the app died before marking it.
    await db.update('event_queue', {'status': EventStatus.sending});

    final queue = EventQueue(db, clock: clock.call);
    expect(await queue.recoverStuck(), 1);
    final batch = await queue.claim('b2');
    final response = await collector.post(
      jsonEncode({
        'batch_id': 'b2',
        'events': [for (final e in batch) e.toJson()],
      }),
    );
    expect(response.accepted, 0);
    expect(response.duplicates, 1);
    expect(await _count(db, 'collected_events'), 1);
  });

  test('every event tracked in lib/ is in the catalogue', () {
    final names = <String>{};
    final pattern = RegExp(r"Analytics\.track\(\s*'([a-z_]+)'");
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) {
        names.addAll(
          pattern.allMatches(f.readAsStringSync()).map((m) => m.group(1)!),
        );
      }
    }
    expect(names, isNotEmpty);
    expect(names.difference(eventSpecs.keys.toSet()), isEmpty);
  });

  test('validation flags missing and unexpected params', () {
    expect(validateEvent('page_view', {'page': 'home'}), isEmpty);
    expect(validateEvent('page_view', {}), ['missing required "page"']);
    expect(validateEvent('page_view', {'page': 'x', 'oops': 1}), [
      'unexpected "oops"',
    ]);
    expect(validateEvent('nope', {}), ['unknown event "nope"']);
  });
}
