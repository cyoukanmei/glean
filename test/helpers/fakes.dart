import 'package:glean/features/reader/data/progress_repository.dart';
import 'package:glean/features/reader/data/reading_time_repository.dart';

/// In-memory progress store for widget tests (no SQLite in fake async).
class FakeProgressRepository implements ProgressRepository {
  FakeProgressRepository({this.saved, this.unfinished});

  /// Returned by [get] for any article.
  ReadingProgress? saved;

  /// Returned by [lastUnfinished].
  (String, ReadingProgress)? unfinished;

  final saves = <ReadingPosition>[];
  int finishedCalls = 0;

  @override
  Future<void> save(
    String userId,
    String articleId,
    ReadingPosition pos,
  ) async => saves.add(pos);

  @override
  Future<bool> markFinished(String userId, String articleId) async =>
      ++finishedCalls == 1;

  @override
  Future<ReadingProgress?> get(String userId, String articleId) async => saved;

  @override
  Future<(String, ReadingProgress)?> lastUnfinished(String userId) async =>
      unfinished;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeReadingTimeRepository implements ReadingTimeRepository {
  int total = 0;

  @override
  Future<int> totalActiveMs(String userId, String articleId) async => total;

  @override
  Future<void> saveSegment({
    required String segmentId,
    required String userId,
    required String articleId,
    required String sessionId,
    required int startedAt,
    required int activeMs,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ReadingProgress progressAt(
  double offset, {
  double progress = 0.5,
  int status = ReadingStatus.reading,
}) => ReadingProgress(
  position: ReadingPosition(
    scrollOffset: offset,
    anchorPara: 0,
    anchorDelta: 0,
    fontScale: 1,
    progress: progress,
  ),
  maxProgress: progress,
  status: status,
  finishedAt: null,
  lastReadAt: 0,
  updatedAt: 0,
);
