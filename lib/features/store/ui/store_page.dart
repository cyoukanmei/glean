import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import '../../../core/design/tabs.dart';
import '../../articles/data/article_repository.dart';
import '../../articles/ui/article_feed.dart';
import '../../articles/ui/labels.dart';
import '../../reader/data/progress_repository.dart';
import '../../reader/ui/open_reader.dart';
import '../../search/search_page.dart';
import 'ranking.dart';
import 'store_banner.dart';

/// 书城: search, category tabs, and on 推荐 the activity banner, quick
/// entries and the ranking card above the feed. The difficulty filter sits
/// on the section header so it does not take first-screen space.
class StorePage extends ConsumerStatefulWidget {
  const StorePage({super.key});

  /// null = all categories (推荐).
  static const tabs = <String?>[
    null,
    'classic',
    'tech',
    'business',
    'culture',
    'daily',
  ];

  @override
  ConsumerState<StorePage> createState() => _StorePageState();
}

class _StorePageState extends ConsumerState<StorePage> {
  int _tab = 0;
  List<StoreBannerItem> _banners = const [];

  @override
  void initState() {
    super.initState();
    _loadBanners();
  }

  void _selectTab(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    Analytics.track('category_switch', {
      'category': StorePage.tabs[i] ?? 'all',
    });
  }

  /// Banners are built from local data, so they work offline: the classics
  /// month, the newest article, this week's most read.
  Future<void> _loadBanners() async {
    final repo = ref.read(articleRepositoryProvider);
    final (classic, newest, top) = await (
      repo.byId('classic-treasure-island-1'),
      repo.ranking(RankBoard.newest, limit: 1),
      repo.ranking(RankBoard.reading, limit: 1),
    ).wait;
    if (!mounted) return;
    setState(() {
      _banners = [
        if (classic != null)
          StoreBannerItem(
            id: 'classics_month',
            tag: '活动',
            title: '十月名著共读月',
            subtitle: '10 部经典的第一章 · 读完 5 篇点亮书签',
            article: classic,
            onTap: () => _selectTab(StorePage.tabs.indexOf('classic')),
          ),
        if (newest.firstOrNull case final a?)
          StoreBannerItem(
            id: 'newest',
            tag: '新上架',
            title: a.title,
            subtitle:
                '${categoryLabels[a.category]} · ${levelLabels[a.level]}'
                ' · 约 ${readingMinutes(a.wordCount)} 分钟',
            article: a,
            onTap: () => openReader(context, a, 'banner'),
          ),
        if (top.firstOrNull case final a?)
          StoreBannerItem(
            id: 'weekly_top',
            tag: '榜单',
            title: '本周热读 TOP 20',
            subtitle: '第一名《${a.title}》· ${compactCount(a.readers)} 人在读',
            article: a,
            onTap: () => openRanking(context, RankBoard.reading),
          ),
      ];
    });
  }

  /// 随便读读: a random article the user has not finished.
  Future<void> _surprise() async {
    final pool = await ref.read(articleRepositoryProvider).page(limit: 60);
    final done = await ref
        .read(progressRepositoryProvider)
        .forArticles(ref.read(currentUserIdProvider), pool.map((a) => a.id));
    final fresh = [
      for (final a in pool)
        if ((done[a.id]?.$2 ?? 0) < ReadingStatus.finished) a,
    ];
    final list = fresh.isEmpty ? pool : fresh;
    if (list.isEmpty || !mounted) return;
    openReader(context, list[Random().nextInt(list.length)], 'surprise');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(feedRevisionProvider, (_, _) => _loadBanners());
    final category = StorePage.tabs[_tab];
    final home = category == null;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ArticleFeed(
          category: category,
          header: [
            const SizedBox(height: 10),
            // A button into the search page; the field flies there.
            Hero(
              tag: 'search-field',
              child: Material(
                type: MaterialType.transparency,
                child: SearchField(
                  key: const Key('home-search'),
                  hint: '搜索文章、名著、正文',
                  onTap: () => openSearch(context),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextTabs(
              key: const Key('category-tabs'),
              labels: [
                for (final c in StorePage.tabs)
                  c == null ? '推荐' : categoryLabels[c]!,
              ],
              selected: _tab,
              onSelected: _selectTab,
            ),
            if (home) ...[
              const SizedBox(height: 14),
              StoreBanner(items: _banners),
              const SizedBox(height: 16),
              _Entries(
                onRanking: () => openRanking(context, RankBoard.reading),
                onClassics: () => _selectTab(StorePage.tabs.indexOf('classic')),
                onNewest: () => openRanking(context, RankBoard.newest),
                onSurprise: _surprise,
              ),
              const SizedBox(height: 16),
              const RankingCard(),
            ],
          ],
          sectionHeader: SectionHeader(
            title: home ? '为你推荐' : '最新文章',
            trailing: const _LevelMenu(),
          ),
        ),
      ),
    );
  }
}

/// Four rounded shortcuts under the banner.
class _Entries extends StatelessWidget {
  const _Entries({
    required this.onRanking,
    required this.onClassics,
    required this.onNewest,
    required this.onSurprise,
  });

  final VoidCallback onRanking;
  final VoidCallback onClassics;
  final VoidCallback onNewest;
  final VoidCallback onSurprise;

  @override
  Widget build(BuildContext context) {
    Widget entry(
      String key,
      IconData icon,
      Color color,
      String label,
      VoidCallback onTap,
    ) => Expanded(
      child: PressableScale(
        key: Key('entry-$key'),
        onTap: () {
          Analytics.track('store_entry', {'entry': key});
          onTap();
        },
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: GleanColors.dark ? 0.22 : 0.13),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: GleanColors.label),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          entry(
            'ranking',
            Icons.emoji_events_rounded,
            const Color(0xFFE0603A),
            '排行榜',
            onRanking,
          ),
          entry(
            'classics',
            Icons.menu_book_rounded,
            GleanColors.tintBright,
            '名著馆',
            onClassics,
          ),
          entry(
            'newest',
            Icons.auto_awesome_rounded,
            const Color(0xFFD9A23E),
            '新上架',
            onNewest,
          ),
          entry(
            'surprise',
            CupertinoIcons.shuffle,
            const Color(0xFF5B7BD5),
            '随便读读',
            onSurprise,
          ),
        ],
      ),
    );
  }
}

/// "全部难度 ▾": opens an action sheet with one choice per level.
class _LevelMenu extends ConsumerWidget {
  const _LevelMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levels = ref.watch(levelFilterProvider);
    final single = levels.length == 1 ? levels.single : null;
    final label = levels.length == LevelFilter.all.length
        ? '全部难度'
        : [
            for (final l in levelLabels.keys)
              if (levels.contains(l)) levelLabels[l]!,
          ].join('/');

    Future<void> pick() async {
      final notifier = ref.read(levelFilterProvider.notifier);
      final choice = await showCupertinoModalPopup<int>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          title: const Text('按难度筛选'),
          actions: [
            for (final (value, text) in [
              (0, '全部难度'),
              for (final e in levelLabels.entries) (e.key, e.value),
            ])
              CupertinoActionSheetAction(
                key: Key('level-option-$value'),
                isDefaultAction: value == (single ?? 0),
                onPressed: () => Navigator.pop(context, value),
                child: Text(text),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ),
      );
      if (choice == null) return;
      notifier.select(choice == 0 ? null : choice);
      Analytics.track('level_filter', {'level': choice});
    }

    return GestureDetector(
      key: const Key('level-menu'),
      behavior: HitTestBehavior.opaque,
      onTap: pick,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: GleanColors.tint,
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 18, color: GleanColors.tint),
          ],
        ),
      ),
    );
  }
}
