import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/widgets/stagger_in.dart';
import '../../../core/widgets/state_illustration.dart';
import '../../reader/ui/continue_reading_card.dart';
import '../../reader/ui/open_reader.dart';
import '../data/article_repository.dart';
import 'article_card.dart';

/// One category tab: keyset-paged list with skeleton, stagger-in,
/// pull-to-refresh and load-more.
class ArticleFeed extends ConsumerStatefulWidget {
  const ArticleFeed({super.key, required this.category});

  /// null = all categories.
  final String? category;

  String get surface => category ?? 'all';

  @override
  ConsumerState<ArticleFeed> createState() => _ArticleFeedState();
}

class _ArticleFeedState extends ConsumerState<ArticleFeed>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  static const pageSize = 10;

  /// Local reads are usually far below this, so the skeleton only shows when
  /// loading is actually perceptible (e.g. first-launch seed import); once
  /// shown it stays long enough not to flash.
  static const showSkeletonAfter = Duration(milliseconds: 120);
  static const minSkeleton = Duration(milliseconds: 400);
  static const fadeOut = Duration(milliseconds: 120);

  /// Demo/recording only: `--dart-define=SLOW_LOAD=800` delays every read.
  static const _slowLoadMs = int.fromEnvironment('SLOW_LOAD');

  late final AnimationController _stagger = AnimationController(
    vsync: this,
    duration: StaggerIn.totalDuration,
  );

  List<ArticleSummary> _items = const [];
  bool _loaded = false;
  bool _skeleton = false;
  bool _failed = false;
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _refreshing = false;
  bool _fadedOut = false;

  /// Leading items of the current load that cascade in.
  int _staggered = 0;

  /// Bumped on every reload; results of superseded loads are dropped.
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _stagger.dispose();
    super.dispose();
  }

  Future<List<ArticleSummary>> _fetch({FeedCursor? after}) async {
    if (_slowLoadMs > 0) {
      await Future<void>.delayed(const Duration(milliseconds: _slowLoadMs));
    }
    return ref
        .read(articleRepositoryProvider)
        .page(
          category: widget.category,
          levels: ref.read(levelFilterProvider),
          after: after,
          limit: pageSize,
        );
  }

  Future<void> _reload({bool fade = false}) async {
    final gen = ++_generation;
    if (fade && _items.isNotEmpty) {
      setState(() => _fadedOut = true);
      await Future<void>.delayed(fadeOut);
      if (!mounted || gen != _generation) return;
    }

    // Completes [minSkeleton] after the skeleton appeared; awaited after the
    // data arrives so a shown skeleton never just flashes.
    Future<void>? skeletonMinShown;
    final skeletonTimer = Timer(showSkeletonAfter, () {
      if (!mounted || gen != _generation) return;
      skeletonMinShown = Future<void>.delayed(minSkeleton);
      setState(() {
        _skeleton = true;
        // The old list faded out for a filter change; fade the skeleton in.
        _fadedOut = false;
      });
    });

    List<ArticleSummary>? page;
    try {
      page = await _fetch();
    } catch (e, st) {
      debugPrint('[feed] load failed: $e\n$st');
    }
    skeletonTimer.cancel();
    await skeletonMinShown;
    if (!mounted || gen != _generation) return;

    setState(() {
      _loaded = true;
      _skeleton = false;
      _fadedOut = false;
      _loadingMore = false;
      _failed = page == null;
      _items = page ?? const [];
      _hasMore = (page?.length ?? 0) == pageSize;
      _staggered = min(_items.length, StaggerIn.maxItems);
    });
    _stagger.forward(from: 0);
  }

  Future<void> _loadMore() async {
    if (!_loaded || _loadingMore || !_hasMore || _items.isEmpty) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    final List<ArticleSummary> page;
    try {
      page = await _fetch(after: _items.last.cursor);
    } catch (e) {
      debugPrint('[feed] load more failed: $e');
      if (mounted && gen == _generation) setState(() => _loadingMore = false);
      return;
    }
    if (!mounted || gen != _generation) return;
    setState(() {
      _items = [..._items, ...page];
      _hasMore = page.length == pageSize;
      _loadingMore = false;
    });
  }

  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));

    if (!(ref.read(onlineProvider).value ?? true)) {
      Analytics.track('offline_hit', {'surface': widget.surface});
      say('当前离线，显示的是本地内容');
      return;
    }
    _refreshing = true;
    try {
      final repo = ref.read(articleRepositoryProvider);
      final fresh = await ref
          .read(articleRemoteProvider)
          .fetchLatest(repo.knownIds);
      await repo.upsertAll(fresh);
      say(fresh.isEmpty ? '已是最新' : '更新了 ${fresh.length} 篇文章');
      if (fresh.isNotEmpty) ref.read(feedRevisionProvider.notifier).bump();
      await _reload();
    } catch (e) {
      debugPrint('[feed] refresh failed: $e');
      say('刷新失败，显示的是本地内容');
    } finally {
      _refreshing = false;
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n.metrics.extentAfter < 600) _loadMore();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen(levelFilterProvider, (_, _) => _reload(fade: true));
    ref.listen(feedRevisionProvider, (_, _) {
      if (!_refreshing) _reload();
    });

    // 推荐 (all categories) opens with the "continue reading" card.
    final showContinue = widget.category == null;
    final Widget body;
    if (_skeleton) {
      body = const ArticleListSkeleton();
    } else if (!_loaded) {
      body = const SizedBox.expand();
    } else if (_items.isEmpty) {
      final offline = ref.watch(onlineProvider).value == false;
      body = _Message(
        StateIllustration(
          asset: offline
              ? StateIllustration.offline
              : StateIllustration.emptyArticles,
          title: _failed ? '加载失败' : '没有符合条件的文章',
          message: _failed ? '下拉重试' : '换个难度试试，或下拉看看有没有新文章',
        ),
      );
    } else {
      body = NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _items.length + 1 + (showContinue ? 1 : 0),
          itemBuilder: (context, index) {
            if (showContinue) {
              if (index == 0) return const ContinueReadingCard();
              index--;
            }
            final i = index;
            if (i == _items.length) {
              return _Footer(loading: _loadingMore, end: !_hasMore);
            }
            final card = ArticleCard(
              article: _items[i],
              surface: widget.surface,
              onTap: () => openReader(context, _items[i], widget.surface),
            );
            return i < _staggered
                ? StaggerIn(animation: _stagger, index: i, child: card)
                : card;
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: AnimatedOpacity(
        opacity: _fadedOut ? 0 : 1,
        duration: fadeOut,
        child: body,
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.loading, required this.end});

  final bool loading;
  final bool end;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Center(
        child: loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : end
            ? Text('没有更多了', style: Theme.of(context).textTheme.labelSmall)
            : null,
      ),
    );
  }
}

/// Scrollable so pull-to-refresh still works on an empty list.
class _Message extends StatelessWidget {
  const _Message(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 64),
        Center(child: child),
      ],
    );
  }
}
