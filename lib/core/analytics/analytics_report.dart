import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Analysis queries over `collected_events` (the mock warehouse).
///
/// Computed in Dart so they run on any Android SQLite build; the equivalent
/// SQL (SQLite JSON1) is in [sql] and in the README.
class AnalyticsReport {
  AnalyticsReport(this._db);

  final DatabaseExecutor _db;

  static const sql = {
    'reading': '''
SELECT date(ts / 1000, 'unixepoch', 'localtime') AS day,
       ROUND(SUM(json_extract(params, '\$.active_ms')) / 60000.0, 1) AS minutes,
       COUNT(*) AS reads
FROM collected_events
WHERE name = 'read_duration' AND ts >= :since
GROUP BY day ORDER BY day;''',
    'funnel': '''
WITH opened AS (
  SELECT DISTINCT user_id, json_extract(params, '\$.article_id') AS a
  FROM collected_events WHERE name = 'article_open' AND ts >= :since),
half AS (
  SELECT DISTINCT user_id, json_extract(params, '\$.article_id') AS a
  FROM collected_events WHERE name = 'scroll_depth'
    AND json_extract(params, '\$.depth') >= 50 AND ts >= :since),
done AS (
  SELECT DISTINCT user_id, json_extract(params, '\$.article_id') AS a
  FROM collected_events WHERE name = 'article_finish' AND ts >= :since)
SELECT (SELECT COUNT(*) FROM opened) AS opened,
       (SELECT COUNT(*) FROM half JOIN opened USING (user_id, a)) AS read_half,
       (SELECT COUNT(*) FROM done JOIN opened USING (user_id, a)) AS finished;''',
    'ctr': '''
SELECT json_extract(params, '\$.surface') AS surface,
       SUM(name = 'article_impression') AS impressions,
       SUM(name = 'article_open') AS opens
FROM collected_events
WHERE name IN ('article_impression', 'article_open') AND ts >= :since
GROUP BY surface ORDER BY impressions DESC;''',
  };

  Future<List<(String event, Map<String, Object?> params, int ts, String?)>>
  _events(Set<String> names, int since) async {
    final rows = await _db.query(
      'collected_events',
      columns: ['name', 'params', 'ts', 'user_id'],
      where:
          'name IN (${List.filled(names.length, '?').join(', ')}) AND ts >= ?',
      whereArgs: [...names, since],
    );
    return [
      for (final r in rows)
        (
          r['name']! as String,
          (jsonDecode(r['params']! as String) as Map).cast<String, Object?>(),
          r['ts']! as int,
          r['user_id'] as String?,
        ),
    ];
  }

  /// Minutes read per local day over the last [days] days (oldest first,
  /// days without reading included as 0).
  Future<List<(DateTime day, double minutes, int reads)>> readingByDay(
    DateTime now, {
    int days = 7,
  }) async {
    final today = DateTime(now.year, now.month, now.day);
    final first = today.subtract(Duration(days: days - 1));
    final events = await _events({
      'read_duration',
    }, first.millisecondsSinceEpoch);
    final ms = <DateTime, int>{};
    final reads = <DateTime, int>{};
    for (final (_, params, ts, _) in events) {
      final d = DateTime.fromMillisecondsSinceEpoch(ts);
      final day = DateTime(d.year, d.month, d.day);
      ms[day] = (ms[day] ?? 0) + ((params['active_ms'] as num?)?.toInt() ?? 0);
      reads[day] = (reads[day] ?? 0) + 1;
    }
    return [
      for (var i = 0; i < days; i++)
        if (DateTime(first.year, first.month, first.day + i) case final day)
          (day, (ms[day] ?? 0) / 60000, reads[day] ?? 0),
    ];
  }

  /// Distinct (user, article) pairs opened, read to 50 %, and finished.
  Future<(int opened, int readHalf, int finished)> funnel(int since) async {
    final events = await _events({
      'article_open',
      'scroll_depth',
      'article_finish',
    }, since);
    final opened = <String>{};
    final half = <String>{};
    final done = <String>{};
    for (final (name, params, _, user) in events) {
      final key = '$user/${params['article_id']}';
      switch (name) {
        case 'article_open':
          opened.add(key);
        case 'scroll_depth' when ((params['depth'] as num?) ?? 0) >= 50:
          half.add(key);
        case 'article_finish':
          done.add(key);
      }
    }
    return (
      opened.length,
      half.intersection(opened).length,
      done.intersection(opened).length,
    );
  }

  /// Impressions and opens per list surface.
  Future<List<(String surface, int impressions, int opens)>> clickThrough(
    int since,
  ) async {
    final events = await _events({'article_impression', 'article_open'}, since);
    final imp = <String, int>{};
    final opens = <String, int>{};
    for (final (name, params, _, _) in events) {
      final s = '${params['surface']}';
      if (name == 'article_impression') {
        imp[s] = (imp[s] ?? 0) + 1;
      } else {
        opens[s] = (opens[s] ?? 0) + 1;
      }
    }
    final surfaces = {...imp.keys, ...opens.keys}.toList()
      ..sort((a, b) => (imp[b] ?? 0).compareTo(imp[a] ?? 0));
    return [for (final s in surfaces) (s, imp[s] ?? 0, opens[s] ?? 0)];
  }
}
