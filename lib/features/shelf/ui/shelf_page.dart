import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/home_tab.dart';
import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import '../../../core/design/tabs.dart';
import '../../../core/widgets/stagger_in.dart';
import '../../articles/data/article_repository.dart';
import '../../articles/ui/book_tile.dart';
import '../../library/ui/article_actions.dart';
import '../../reader/ui/continue_reading_card.dart';
import '../../reader/ui/open_reader.dart';
import '../../search/search_page.dart';
import '../application/shelf.dart';

/// 书架: the quickest way back into a book. "Continue reading" on top, then
/// every book the user opened, starred or saved, as a cover grid (most
/// recent first) with progress on the covers, filtered by 在读 / 收藏 /
/// 稍后 / 读完. An empty shelf shows what others are reading instead.
class ShelfPage extends ConsumerStatefulWidget {
  const ShelfPage({super.key});

  static const surface = 'shelf';

  @override
  ConsumerState<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends ConsumerState<ShelfPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _stagger = AnimationController(
    vsync: this,
    duration: StaggerIn.totalDuration,
  );

  List<ShelfEntry>? _entries;
  List<ArticleSummary> _popular = const [];
  ShelfFilter _filter = ShelfFilter.all;

  @override
  void initState() {
    super.initState();
    _load(animate: true);
  }

  @override
  void dispose() {
    _stagger.dispose();
    super.dispose();
  }

  Future<void> _load({bool animate = false}) async {
    final entries = await loadShelf(
      userId: ref.read(currentUserIdProvider),
      progress: ref.read(progressRepositoryProvider),
      marks: ref.read(marksRepositoryProvider),
    );
    final popular = entries.isEmpty
        ? await ref
              .read(articleRepositoryProvider)
              .ranking(RankBoard.reading, limit: 6)
        : const <ArticleSummary>[];
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _popular = popular;
    });
    if (animate) _stagger.forward(from: 0);
  }

  void _setFilter(ShelfFilter f) {
    setState(() => _filter = f);
    _stagger.forward(from: 0);
    Analytics.track('shelf_filter', {'filter': f.name});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(progressRevisionProvider, (_, _) => _load());
    ref.listen(marksRevisionProvider, (_, _) => _load());
    final entries = _entries;
    final shown = entries?.where((e) => e.matches(_filter)).toList();
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverList.list(
              children: [
                const SizedBox(height: 8),
                LargeTitle(
                  title: '书架',
                  trailing: IconButton(
                    key: const Key('shelf-search'),
                    onPressed: () => openSearch(context),
                    icon: Icon(
                      Icons.search_rounded,
                      size: 26,
                      color: GleanColors.label,
                    ),
                  ),
                ),
                const ContinueReadingCard(),
                const SizedBox(height: 18),
                if (entries != null && entries.isNotEmpty) ...[
                  PillTabs<ShelfFilter>(
                    key: const Key('shelf-filters'),
                    value: _filter,
                    items: {for (final f in ShelfFilter.values) f: f.label},
                    counts: {
                      for (final f in ShelfFilter.values)
                        f: entries.where((e) => e.matches(f)).length,
                    },
                    onChanged: _setFilter,
                  ),
                  const SizedBox(height: 18),
                ],
              ],
            ),
            if (entries == null)
              const SliverToBoxAdapter()
            else if (entries.isEmpty)
              ..._emptyShelf(context)
            else if (shown!.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Center(
                    child: Text(
                      switch (_filter) {
                        ShelfFilter.reading => '没有在读的书',
                        ShelfFilter.favorite => '还没有收藏，长按封面就能收藏',
                        ShelfFilter.later => '没有稍后再读的书',
                        ShelfFilter.finished => '还没有读完的书',
                        ShelfFilter.all => '',
                      },
                      style: TextStyle(
                        fontSize: 14.5,
                        color: GleanColors.label2,
                      ),
                    ),
                  ),
                ),
              )
            else
              _grid(
                context,
                count: shown.length,
                builder: (i) {
                  final e = shown[i];
                  return BookTile(
                    key: ValueKey(e.article.id),
                    article: e.article,
                    surface: ShelfPage.surface,
                    starred: e.favorite,
                    badge: e.finished
                        ? '读完'
                        : e.progress > 0
                        ? '${(e.progress * 100).round().clamp(1, 99)}%'
                        : '未读',
                    badgeAccent: e.finished,
                    onTap: () =>
                        openReader(context, e.article, ShelfPage.surface),
                    onLongPress: () => showArticleActions(
                      context,
                      ref,
                      e.article,
                      surface: ShelfPage.surface,
                    ),
                  );
                },
              ),
            SliverPadding(padding: EdgeInsets.only(bottom: bottom + 28)),
          ],
        ),
      ),
    );
  }

  /// Three covers per row; the first screen cascades in.
  Widget _grid(
    BuildContext context, {
    required int count,
    required Widget Function(int) builder,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          const columns = 3;
          const gap = 14.0;
          final w =
              (constraints.crossAxisExtent - gap * (columns - 1)) / columns;
          return SliverGrid.builder(
            itemCount: count,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: gap,
              mainAxisSpacing: 18,
              mainAxisExtent: w * 4 / 3 + BookTile.textHeight(context),
            ),
            itemBuilder: (context, i) => i < StaggerIn.maxItems
                ? StaggerIn(animation: _stagger, index: i, child: builder(i))
                : builder(i),
          );
        },
      ),
    );
  }

  List<Widget> _emptyShelf(BuildContext context) => [
    SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: GleanColors.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: GleanColors.cardShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '书架还空着',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: GleanColors.label,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '读过、收藏或稍后再读的文章都会放在这里',
                    style: TextStyle(fontSize: 13, color: GleanColors.label2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            PressableScale(
              key: const Key('shelf-go-store'),
              onTap: () => ref.read(homeTabProvider.notifier).go(HomeTab.store),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: GleanColors.tint,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  '去书城',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    if (_popular.isNotEmpty) ...[
      const SliverToBoxAdapter(child: SectionHeader(title: '大家都在读')),
      _grid(
        context,
        count: _popular.length,
        builder: (i) {
          final a = _popular[i];
          return BookTile(
            article: a,
            surface: '${ShelfPage.surface}-popular',
            meta: '${a.readers} 人在读',
            onTap: () => openReader(context, a, '${ShelfPage.surface}-popular'),
          );
        },
      ),
    ],
  ];
}
