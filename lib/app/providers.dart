import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../features/articles/data/article_remote.dart';
import '../features/articles/data/article_repository.dart';
import '../features/reader/data/progress_repository.dart';
import '../features/reader/data/reading_time_repository.dart';

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

/// Bumped after the reader flushes progress, so "continue reading" refreshes.
class ProgressRevision extends Notifier<int> {
  @override
  int build() => 0;

  /// Called from a write that outlives the reader; the scope may be gone.
  void bump() {
    if (ref.mounted) state++;
  }
}

final progressRevisionProvider = NotifierProvider<ProgressRevision, int>(
  ProgressRevision.new,
);

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
    state = next;
    ref.read(prefsProvider).setStringList(_key, [for (final l in next) '$l']);
  }
}

final levelFilterProvider = NotifierProvider<LevelFilter, Set<int>>(
  LevelFilter.new,
);

/// Bumped when articles were added (e.g. by a refresh in one tab) so every
/// kept-alive feed reloads, not only the one that was pulled.
class FeedRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final feedRevisionProvider = NotifierProvider<FeedRevision, int>(
  FeedRevision.new,
);
