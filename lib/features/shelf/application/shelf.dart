import 'dart:math';

import '../../articles/data/article_repository.dart';
import '../../library/data/marks_repository.dart';
import '../../reader/data/progress_repository.dart';

/// 书架 filters, in display order.
enum ShelfFilter {
  all('全部'),
  reading('在读'),
  favorite('收藏'),
  later('稍后'),
  finished('读完');

  const ShelfFilter(this.label);

  final String label;
}

/// One book on the shelf: anything the user opened, starred or saved for
/// later.
class ShelfEntry {
  const ShelfEntry({
    required this.article,
    required this.lastAt,
    this.progress = 0,
    this.status = ReadingStatus.unread,
    this.favorite = false,
    this.later = false,
  });

  final ArticleSummary article;

  /// Last time the user did anything with it (read, starred, saved).
  final int lastAt;
  final double progress;
  final int status;
  final bool favorite;
  final bool later;

  bool get finished => status == ReadingStatus.finished;
  bool get started => progress > 0 && !finished;

  bool matches(ShelfFilter f) => switch (f) {
    ShelfFilter.all => true,
    ShelfFilter.reading => started,
    ShelfFilter.favorite => favorite,
    ShelfFilter.later => later,
    ShelfFilter.finished => finished,
  };
}

/// Merges reading history with 收藏 / 稍后再读 into one list, most recent
/// activity first.
Future<List<ShelfEntry>> loadShelf({
  required String userId,
  required ProgressRepository progress,
  required MarksRepository marks,
}) async {
  final (history, favorites, later) = await (
    progress.history(userId),
    marks.list(userId, MarkKind.favorite),
    marks.list(userId, MarkKind.later),
  ).wait;
  final byId = <String, ShelfEntry>{};
  for (final (a, p) in history) {
    byId[a.id] = ShelfEntry(
      article: a,
      lastAt: p.lastReadAt,
      progress: p.maxProgress,
      status: p.status,
    );
  }
  void mark(List<(ArticleSummary, int)> list, {required bool favorite}) {
    for (final (a, at) in list) {
      final e = byId[a.id];
      byId[a.id] = ShelfEntry(
        article: a,
        lastAt: max(e?.lastAt ?? 0, at),
        progress: e?.progress ?? 0,
        status: e?.status ?? ReadingStatus.unread,
        favorite: favorite || (e?.favorite ?? false),
        later: !favorite || (e?.later ?? false),
      );
    }
  }

  mark(favorites, favorite: true);
  mark(later, favorite: false);
  return byId.values.toList()..sort((a, b) => b.lastAt.compareTo(a.lastAt));
}
