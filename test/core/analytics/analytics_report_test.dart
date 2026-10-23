import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glean/core/analytics/analytics_report.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_db.dart';

var _n = 0;

Future<void> _event(
  Database db,
  String name,
  DateTime at,
  Map<String, Object?> params, {
  String user = 'u1',
}) => db.insert('collected_events', {
  'event_id': 'e${_n++}',
  'name': name,
  'ts': at.millisecondsSinceEpoch,
  'session_id': 's1',
  'user_id': user,
  'params': jsonEncode(params),
  'received_at': at.millisecondsSinceEpoch,
});

void main() {
  final now = DateTime(2026, 10, 23, 20);
  final since = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;

  Future<Database> seeded() async {
    final db = await openTestDb();
    final today = DateTime(2026, 10, 23, 9);
    final yesterday = DateTime(2026, 10, 22, 21);
    // u1 opens a1 (reads half, finishes) and a2 (bounces); u2 opens a1.
    await _event(db, 'article_open', today, {
      'article_id': 'a1',
      'surface': 'all',
    });
    await _event(db, 'scroll_depth', today, {'article_id': 'a1', 'depth': 50});
    await _event(db, 'article_finish', today, {'article_id': 'a1'});
    await _event(db, 'read_duration', today, {
      'article_id': 'a1',
      'active_ms': 180000,
      'max_progress': 1.0,
    });
    await _event(db, 'article_open', yesterday, {
      'article_id': 'a2',
      'surface': 'tech',
    });
    await _event(db, 'read_duration', yesterday, {
      'article_id': 'a2',
      'active_ms': 30000,
      'max_progress': 0.1,
    });
    await _event(db, 'article_open', today, {
      'article_id': 'a1',
      'surface': 'all',
    }, user: 'u2');
    for (var i = 0; i < 4; i++) {
      await _event(db, 'article_impression', today, {
        'article_id': 'a$i',
        'surface': 'all',
        'position': i,
      });
    }
    // Older than the 7-day window: ignored.
    await _event(db, 'article_open', DateTime(2026, 10, 1), {
      'article_id': 'old',
      'surface': 'all',
    });
    return db;
  }

  test('7-day reading minutes per local day, zero days included', () async {
    final report = AnalyticsReport(await seeded());
    final days = await report.readingByDay(now);
    expect(days, hasLength(7));
    expect(days.last.$1, DateTime(2026, 10, 23));
    expect(days.last.$2, 3.0);
    expect(days[5].$2, 0.5);
    expect(days.first.$2, 0);
  });

  test('funnel counts distinct (user, article) pairs', () async {
    final report = AnalyticsReport(await seeded());
    expect(await report.funnel(since), (3, 1, 1));
  });

  test('click-through per surface', () async {
    final report = AnalyticsReport(await seeded());
    expect(await report.clickThrough(since), [('all', 4, 2), ('tech', 0, 1)]);
  });

  test('the README SQL gives the same numbers (SQLite JSON1)', () async {
    final db = await seeded();
    final funnel = (await db.rawQuery(
      AnalyticsReport.sql['funnel']!.replaceAll(':since', '$since'),
    )).single;
    expect(funnel, {'opened': 3, 'read_half': 1, 'finished': 1});

    final ctr = await db.rawQuery(
      AnalyticsReport.sql['ctr']!.replaceAll(':since', '$since'),
    );
    expect(ctr.first, {'surface': 'all', 'impressions': 4, 'opens': 2});

    final reading = await db.rawQuery(
      AnalyticsReport.sql['reading']!.replaceAll(':since', '$since'),
    );
    expect(reading.map((r) => r['minutes']), [0.5, 3.0]);
  });
}
