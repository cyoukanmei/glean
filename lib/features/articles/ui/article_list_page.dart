import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/widgets/offline_banner.dart';
import 'article_feed.dart';
import 'labels.dart';

/// Home: category tabs, difficulty filter and one paged feed per tab.
class ArticleListPage extends ConsumerStatefulWidget {
  const ArticleListPage({super.key});

  /// null = all categories.
  static const tabs = <String?>[null, 'tech', 'business', 'culture', 'daily'];

  @override
  ConsumerState<ArticleListPage> createState() => _ArticleListPageState();
}

class _ArticleListPageState extends ConsumerState<ArticleListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: ArticleListPage.tabs.length,
    vsync: this,
  )..addListener(_onTabChanged);

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    Analytics.track('category_switch', {
      'category': ArticleListPage.tabs[_tabs.index] ?? 'all',
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(onlineProvider).value == false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('拾读'),
        bottom: TabBar(
          controller: _tabs,
          // The indicator stretches towards the next tab and then catches up,
          // tracking the TabBarView swipe frame by frame.
          indicatorAnimation: TabIndicatorAnimation.elastic,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: [
            for (final c in ArticleListPage.tabs)
              Tab(text: c == null ? '推荐' : categoryLabels[c]),
          ],
        ),
      ),
      body: Column(
        children: [
          OfflineBanner(offline: offline),
          const _LevelFilterBar(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final c in ArticleListPage.tabs)
                  ArticleFeed(key: PageStorageKey(c ?? 'all'), category: c),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelFilterBar extends ConsumerWidget {
  const _LevelFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(levelFilterProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          for (final level in levelLabels.keys) ...[
            FilterChip(
              label: Text(levelLabels[level]!),
              selected: selected.contains(level),
              // The last selected level cannot be turned off.
              onSelected: selected.length == 1 && selected.contains(level)
                  ? null
                  : (_) => ref.read(levelFilterProvider.notifier).toggle(level),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
