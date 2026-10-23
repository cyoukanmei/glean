import 'dart:convert';

import '../../../core/clock.dart';

/// Stand-in for the article API (no backend in this project).
///
/// Serves a small bundled pool of "newly published" articles: each call
/// releases at most [batchSize] articles the device does not have yet,
/// stamped with the current time so they land at the top of the feed.
class MockArticleRemote {
  MockArticleRemote({
    required this._loadPool,
    this.latency = const Duration(milliseconds: 600),
    this.batchSize = 2,
    this._clock = systemClock,
  });

  final Future<String> Function() _loadPool;
  final Duration latency;
  final int batchSize;
  final Clock _clock;

  List<Map<String, Object?>>? _pool;

  /// Returns up to [batchSize] pool articles whose ids are not in [known].
  Future<List<Map<String, Object?>>> fetchLatest(
    Future<Set<String>> Function(Iterable<String> ids) known,
  ) async {
    await Future<void>.delayed(latency);
    final pool = _pool ??= (jsonDecode(await _loadPool()) as List)
        .cast<Map<String, Object?>>();
    final have = await known(pool.map((a) => a['id']! as String));
    final now = _clock();
    return [
      for (final (i, a) in pool.where((a) => !have.contains(a['id'])).indexed)
        if (i < batchSize) {...a, 'published_at': now - i},
    ];
  }
}
