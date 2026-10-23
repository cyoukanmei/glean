import 'package:glean/features/reader/data/progress_repository.dart';
import 'package:glean/features/reader/data/reading_time_repository.dart';
import 'package:glean/features/vocab/data/dictionary_repository.dart';
import 'package:glean/features/vocab/data/vocab_repository.dart';

/// Dictionary with a fixed word list; lookups are case-insensitive.
class FakeDictionaryRepository implements DictionaryRepository {
  FakeDictionaryRepository([this.entries = const {}]);

  /// word -> (lemma, definition)
  final Map<String, (String, String)> entries;

  @override
  Future<DictEntry?> lookup(String raw) async {
    final word = raw.toLowerCase();
    final e = entries[word];
    return e == null
        ? null
        : DictEntry(word: word, lemma: e.$1, phonetic: 'ph', definition: e.$2);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// In-memory word list with the same collect / delete / restore rules as
/// the SQLite one (one row per lemma, soft delete).
class FakeVocabRepository implements VocabRepository {
  final items = <VocabItem>[];
  final deleted = <String>{};
  int _ids = 0;

  Iterable<VocabItem> get _active =>
      items.where((i) => !deleted.contains(i.id));

  @override
  Future<void> collect({
    required String userId,
    required String word,
    required String lemma,
    required String definition,
    required WordSource source,
  }) async {
    final existing = items.where((i) => i.lemma == lemma).firstOrNull;
    if (existing != null) {
      deleted.remove(existing.id);
      return;
    }
    items.add(
      VocabItem(
        id: 'v${_ids++}',
        word: word,
        lemma: lemma,
        definition: definition,
        source: source,
        status: 0,
        createdAt: _ids,
        articleTitle: 'Title of ${source.articleId}',
      ),
    );
  }

  @override
  Future<void> delete(String id) async => deleted.add(id);

  @override
  Future<void> restore(String id) async => deleted.remove(id);

  @override
  Future<bool> isCollected(String userId, String lemma) async =>
      _active.any((i) => i.lemma == lemma);

  @override
  Future<VocabItem?> find(String userId, String lemma) async =>
      _active.where((i) => i.lemma == lemma).firstOrNull;

  @override
  Future<List<VocabItem>> list(String userId) async =>
      _active.toList().reversed.toList();

  @override
  Future<Set<String>> collectedForms(String userId) async => {
    for (final i in _active) ...[i.word.toLowerCase(), i.lemma],
  };

  @override
  Future<int> countFromArticle(String userId, String articleId) async =>
      _active.where((i) => i.source.articleId == articleId).length;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  /// Returned by [forArticles], filtered to the requested ids.
  final cards = <String, (double, int)>{};

  @override
  Future<Map<String, (double, int)>> forArticles(
    String userId,
    Iterable<String> articleIds,
  ) async => {for (final id in articleIds) id: ?cards[id]};

  @override
  Future<int> finishedCount(String userId) async => finishedCalls;

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
