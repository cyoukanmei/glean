import 'package:flutter_test/flutter_test.dart';
import 'package:glean/features/profile/application/profile_stats.dart';

ProfileStats _stats(Map<String, int> byDay) => ProfileStats.from(
  msByDay: byDay,
  today: DateTime(2026, 10, 23, 21), // a Friday evening
  finished: 0,
  words: 0,
  totalMs: 0,
  articles: 24,
);

void main() {
  const minute = 60000;

  test('week dots run Monday to Sunday; today is Friday', () {
    final s = _stats({
      '2026-10-19': minute,
      '2026-10-21': 3 * minute,
      '2026-10-23': 6 * minute,
    });
    expect(s.week, [true, false, true, false, true, false, false]);
    expect(s.todayIndex, 4);
    expect(s.todayMs, 6 * minute);
    expect(s.goalProgress, closeTo(0.4, 1e-9));
  });

  test('the streak counts back from today, or from yesterday if today '
      'has no reading yet', () {
    final days = {
      '2026-10-18': minute, // Sunday, before a gap
      '2026-10-20': minute,
      '2026-10-21': minute,
      '2026-10-22': minute,
    };
    expect(_stats(days).streak, 3);
    expect(_stats({...days, '2026-10-23': minute}).streak, 4);
    expect(_stats({'2026-10-21': minute}).streak, 0);
  });

  test('the goal ring stops at full', () {
    expect(_stats({'2026-10-23': 40 * minute}).goalProgress, 1);
  });

  test('streaks cross month boundaries', () {
    final s = ProfileStats.from(
      msByDay: {'2026-10-31': minute, '2026-11-01': minute},
      today: DateTime(2026, 11, 1, 9),
      finished: 0,
      words: 0,
      totalMs: 0,
      articles: 0,
    );
    expect(s.streak, 2);
  });
}
