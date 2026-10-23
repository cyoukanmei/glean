import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../features/articles/data/article_remote.dart';
import '../features/articles/data/article_repository.dart';
import '../features/reader/data/progress_repository.dart';
import '../features/reader/data/reading_time_repository.dart';
import '../features/vocab/data/dictionary_repository.dart';
import '../features/vocab/data/vocab_repository.dart';

/// Opened in `main` before `runApp`; overridden in the root ProviderScope.
final databaseProvider = Provider<Database>(
  (ref) => throw UnimplementedError('overridden in main'),
);

/// Completes when the seed import finishes (started in `main`, not awaited,
/// so the first launch shows skeletons instead of a blank screen).
final seedReadyProvider = Provider<Future<void>>(
  (ref) => throw UnimplementedError('overridden in main'),
);

final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('overridden in main'),
);

final articleRepositoryProvider = Provider(
  (ref) => ArticleRepository(
    ref.watch(databaseProvider),
    ready: ref.watch(seedReadyProvider),
  ),
);

/// Signed-in user. A fixed local id until login lands; every per-user table
/// already keys on it, so switching to real accounts needs no migration.
final currentUserIdProvider = Provider<String>((ref) => 'guest');

final progressRepositoryProvider = Provider(
  (ref) => ProgressRepository(ref.watch(databaseProvider)),
);

final readingTimeRepositoryProvider = Provider(
  (ref) => ReadingTimeRepository(ref.watch(databaseProvider)),
);

final vocabRepositoryProvider = Provider(
  (ref) => VocabRepository(ref.watch(databaseProvider)),
);

final dictionaryRepositoryProvider = Provider(
  (ref) => DictionaryRepository(ref.watch(databaseProvider)),
);

/// A counter other widgets watch to know "data X changed, reload".
class Revision extends Notifier<int> {
  @override
  int build() => 0;

  /// May be called from a write that outlives its widget; the scope may be
  /// gone by then.
  void bump() {
    if (ref.mounted) state++;
  }
}

/// Bumped after the reader flushes progress, so "continue reading" refreshes.
final progressRevisionProvider = NotifierProvider<Revision, int>(Revision.new);

/// Bumped when a word is collected or removed anywhere, so the word list and
/// the reader's highlights stay in sync.
final vocabRevisionProvider = NotifierProvider<Revision, int>(Revision.new);

final articleRemoteProvider = Provider(
  (ref) => MockArticleRemote(
    loadPool: () => rootBundle.loadString('assets/seed/remote_pool.json'),
  ),
);

/// Whether any network interface is up. Interface state, not a guarantee
/// that the server is reachable; requests still handle their own failures.
final onlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool isOnline(List<ConnectivityResult> r) =>
      r.any((c) => c != ConnectivityResult.none);
  yield isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(isOnline);
});

/// Difficulty levels shown in the feed, persisted across launches.
/// At least one level stays selected.
class LevelFilter extends Notifier<Set<int>> {
  static const _key = 'feed.levels';
  static const all = {1, 2, 3};

  @override
  Set<int> build() {
    final saved = ref.watch(prefsProvider).getStringList(_key);
    final levels = {...?saved?.map(int.tryParse).nonNulls}.intersection(all);
    return levels.isEmpty ? all : levels;
  }

  void toggle(int level) {
    final next = {...state};
    if (!next.remove(level)) next.add(level);
    if (next.isEmpty) return;
    _set(next);
  }

  /// Single choice from the segmented control; null means every level.
  void select(int? level) => _set(level == null ? all : {level});

  void _set(Set<int> levels) {
    if (levels.length == state.length && levels.containsAll(state)) return;
    state = levels;
    ref.read(prefsProvider).setStringList(_key, [for (final l in levels) '$l']);
  }
}

final levelFilterProvider = NotifierProvider<LevelFilter, Set<int>>(
  LevelFilter.new,
);

/// Bumped when articles were added (e.g. by a refresh in one tab) so every
/// kept-alive feed reloads, not only the one that was pulled.
final feedRevisionProvider = NotifierProvider<Revision, int>(Revision.new);
