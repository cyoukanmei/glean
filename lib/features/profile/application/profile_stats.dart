import '../../reader/data/reading_time_repository.dart';

/// Numbers on the 我的 page.
class ProfileStats {
  const ProfileStats({
    required this.todayMs,
    required this.week,
    required this.todayIndex,
    required this.streak,
    required this.finished,
    required this.words,
    required this.totalMs,
    required this.articles,
  });

  final int todayMs;

  /// Monday..Sunday of this week: whether any reading happened that day.
  final List<bool> week;

  /// 0 = Monday.
  final int todayIndex;

  /// Consecutive days with reading, ending today (or yesterday, if today has
  /// none yet: the streak is not broken until the day is over).
  final int streak;
  final int finished;
  final int words;
  final int totalMs;

  /// Articles stored on the device.
  final int articles;

  /// Share of today's goal read so far, capped at 1.
  double goalProgress(int goalMinutes) =>
      (todayMs / (goalMinutes * 60000)).clamp(0.0, 1.0);

  static ProfileStats from({
    required Map<String, int> msByDay,
    required DateTime today,
    required int finished,
    required int words,
    required int totalMs,
    required int articles,
  }) {
    String day(DateTime d) =>
        ReadingTimeRepository.localDay(d.millisecondsSinceEpoch);
    bool read(DateTime d) => (msByDay[day(d)] ?? 0) > 0;
    final midnight = DateTime(today.year, today.month, today.day);
    final monday = midnight.subtract(Duration(days: today.weekday - 1));

    var streak = 0;
    var d = read(midnight)
        ? midnight
        : midnight.subtract(const Duration(days: 1));
    while (read(d)) {
      streak++;
      d = DateTime(d.year, d.month, d.day - 1);
    }

    return ProfileStats(
      todayMs: msByDay[day(midnight)] ?? 0,
      week: [
        for (var i = 0; i < 7; i++)
          read(DateTime(monday.year, monday.month, monday.day + i)),
      ],
      todayIndex: today.weekday - 1,
      streak: streak,
      finished: finished,
      words: words,
      totalMs: totalMs,
      articles: articles,
    );
  }

  /// Days of history the streak looks back over.
  static const lookback = Duration(days: 90);
}
