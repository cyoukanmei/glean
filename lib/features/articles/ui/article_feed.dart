import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/impressions.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/widgets/stagger_in.dart';
import '../../../core/widgets/state_illustration.dart';
import '../../reader/data/progress_repository.dart';
import '../../reader/ui/open_reader.dart';
import '../data/article_repository.dart';
import '../../library/ui/article_actions.dart';
import 'article_card.dart';

/// The 书城 feed: one bouncing scroll view with the page's [header] on top,
/// then a section header and the keyset-paged article group with skeleton, stagger-in, pull-to-refresh and
/// load-more.
///
/// Changing [category], [query] or the level filter fades the list out and
/// reloads it in place; the header stays put.
class ArticleFeed extends ConsumerStatefulWidget {
  const ArticleFeed({
    super.key,
    required this.category,
    this.query = '',
    this.header = const [],
    this.sectionHeader,
  });

  /// null = all categories.
  final String? category;
  final String query;

  /// Box widgets laid out above the feed (large title, search, tabs).
  final List<Widget> header;

  /// Shown between the header and the list.
  final Widget? sectionHeader;

  String get surface => category ?? 'all';

  @override
  ConsumerState<ArticleFeed> createState() => _ArticleFeedState();
}

class _ArticleFeedState extends ConsumerState<ArticleFeed>
    with SingleTickerProviderStateMixin {
  static const pageSize = 10;

  /// Local reads are usually far below this, so the skeleton only shows when
  /// loading is actually perceptible (e.g. first-launch seed import); once
  /// shown it stays long enough not to flash.
  static const showSkeletonAfter = Duration(milliseconds: 120);
  static const minSkeleton = Duration(milliseconds: 400);
  static const fadeOut = Duration(milliseconds: 120);

  /// Demo/recording only: `--dart-define=SLOW_LOAD=800` delays every read.
  static const _slowLoadMs = int.fromEnvironment('SLOW_LOAD');

  /// Impressions are counted per list, so a new category gets a new one.
  late ImpressionTracker _impressions = ImpressionTracker(widget.surface);

  late final AnimationController _stagger = AnimationController(
    vsync: this,
    duration: StaggerIn.totalDuration,
  );

  List<ArticleSummary> _items = const [];
  Map<String, CardProgress> _progress = const {};
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
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(ArticleFeed old) {
    super.didUpdateWidget(old);
    if (old.category != widget.category) {
      _impressions.dispose();
      _impressions = ImpressionTracker(widget.surface);
    }
    if (old.category != widget.category || old.query != widget.query) {
      _reload(fade: true);
    }
  }

  @override
  void dispose() {
    _stagger.dispose();
    _impressions.dispose();
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
          query: widget.query,
          after: after,
          limit: pageSize,
        );
  }

  Future<Map<String, CardProgress>> _fetchProgress(
    List<ArticleSummary> items,
  ) async {
    final rows = await ref
        .read(progressRepositoryProvider)
        .forArticles(ref.read(currentUserIdProvider), items.map((a) => a.id));
    return {
      for (final MapEntry(:key, value: (max, status)) in rows.entries)
        key: CardProgress(
          maxProgress: max,
          finished: status == ReadingStatus.finished,
        ),
    };
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
    var progress = const <String, CardProgress>{};
    try {
      page = await _fetch();
      progress = await _fetchProgress(page);
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
      _progress = progress;
      _hasMore = (page?.length ?? 0) == pageSize;
      _staggered = min(_items.length, StaggerIn.maxItems);
    });
    _stagger.forward(from: 0);
  }

  Future<void> _reloadProgress() async {
    final gen = _generation;
    final progress = await _fetchProgress(_items);
    if (!mounted || gen != _generation) return;
    setState(() => _progress = progress);
  }

  Future<void> _loadMore() async {
    if (!_loaded || _loadingMore || !_hasMore || _items.isEmpty) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    final List<ArticleSummary> page;
    final Map<String, CardProgress> progress;
    try {
      page = await _fetch(after: _items.last.cursor);
      progress = await _fetchProgress(page);
    } catch (e) {
      debugPrint('[feed] load more failed: $e');
      if (mounted && gen == _generation) setState(() => _loadingMore = false);
      return;
    }
    if (!mounted || gen != _generation) return;
    setState(() {
      _items = [..._items, ...page];
      _progress = {..._progress, ...progress};
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
    ref.listen(levelFilterProvider, (_, _) => _reload(fade: true));
    ref.listen(feedRevisionProvider, (_, _) {
      if (!_refreshing) _reload();
    });
    ref.listen(progressRevisionProvider, (_, _) => _reloadProgress());

    final offline = ref.watch(onlineProvider).value == false;

    final Widget content;
    if (_skeleton) {
      content = const SliverToBoxAdapter(child: ArticleListSkeleton());
    } else if (!_loaded) {
      content = const SliverToBoxAdapter();
    } else if (_items.isEmpty) {
      content = SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Center(
            child: StateIllustration(
              asset: offline
                  ? StateIllustration.offline
                  : StateIllustration.emptyArticles,
              title: _failed
                  ? '加载失败'
                  : widget.query.isEmpty
                  ? '没有符合条件的文章'
                  : '没有找到相关文章',
              message: _failed ? '下拉重试' : '换个难度或关键词试试，或下拉看看有没有新文章',
            ),
          ),
        ),
      );
    } else {
      Widget card(
        int i, {
        required bool first,
        required bool last,
        double margin = 16,
      }) {
        final article = _items[i];
        final row = _impressions.wrap(
          articleId: article.id,
          position: i,
          child: GroupedRow(
            first: first,
            last: last,
            margin: margin,
            child: ArticleCard(
              article: article,
              surface: widget.surface,
              progress: _progress[article.id],
              onTap: () => openReader(context, article, widget.surface),
              onLongPress: () => showArticleActions(
                context,
                ref,
                article,
                surface: widget.surface,
              ),
            ),
          ),
        );
        return i < _staggered
            ? StaggerIn(animation: _stagger, index: i, child: row)
            : row;
      }

      // One grouped list on a phone; in a wide window, separate cards in
      // rows of two or three.
      content = SliverLayoutBuilder(
        builder: (context, box) {
          final columns = (box.crossAxisExtent / 440).floor().clamp(1, 3);
          if (columns == 1) {
            return SliverList.builder(
              itemCount: _items.length,
              itemBuilder: (context, i) =>
                  card(i, first: i == 0, last: i == _items.length - 1),
            );
          }
          return SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            sliver: SliverList.builder(
              itemCount: (_items.length / columns).ceil(),
              itemBuilder: (context, row) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var c = 0; c < columns; c++)
                      Expanded(
                        child: row * columns + c < _items.length
                            ? card(
                                row * columns + c,
                                first: true,
                                last: true,
                                margin: 6,
                              )
                            : const SizedBox(),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    final bottom = MediaQuery.paddingOf(context).bottom;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          CupertinoSliverRefreshControl(onRefresh: _refresh),
          SliverList.list(children: widget.header),
          SliverToBoxAdapter(child: _OfflineStrip(offline: offline)),
          if (widget.sectionHeader case final header?)
            SliverToBoxAdapter(child: header),
          SliverAnimatedOpacity(
            opacity: _fadedOut ? 0 : 1,
            duration: fadeOut,
            sliver: content,
          ),
          if (_loaded && _items.isNotEmpty)
            SliverToBoxAdapter(
              child: _Footer(loading: _loadingMore, end: !_hasMore),
            ),
          SliverPadding(padding: EdgeInsets.only(bottom: bottom + 8)),
        ],
      ),
    );
  }
}

/// Warm strip that slides open when the device goes offline.
class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip({required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: offline
          ? Container(
              key: const Key('offline-strip'),
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: GleanColors.warnBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    size: 18,
                    color: GleanColors.warnInk,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '离线模式 · 正在显示本地内容',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: GleanColors.warnInk,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
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
            ? const CupertinoActivityIndicator()
            : end
            ? Text(
                '没有更多了',
                style: TextStyle(fontSize: 13, color: GleanColors.label3),
              )
            : null,
      ),
    );
  }
}
