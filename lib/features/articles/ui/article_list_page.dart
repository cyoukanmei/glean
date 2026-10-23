import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import 'article_feed.dart';
import 'category_chips.dart';
import 'labels.dart';

/// Home: large title, search, category capsules and the feed. The difficulty
/// filter sits on the section header so it does not take first-screen space.
class ArticleListPage extends ConsumerStatefulWidget {
  const ArticleListPage({super.key});

  /// null = all categories (推荐).
  static const tabs = <String?>[null, 'tech', 'business', 'culture', 'daily'];

  @override
  ConsumerState<ArticleListPage> createState() => _ArticleListPageState();
}

class _ArticleListPageState extends ConsumerState<ArticleListPage> {
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  static const searchDebounce = Duration(milliseconds: 300);

  final _search = TextEditingController();
  Timer? _debounce;
  int _tab = 0;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _selectTab(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    Analytics.track('category_switch', {
      'category': ArticleListPage.tabs[i] ?? 'all',
    });
  }

  void _onQueryChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () {
      final q = text.trim();
      if (q != _query) setState(() => _query = q);
    });
  }

  String get _eyebrow {
    final now = clock.now();
    return '${now.month}月${now.day}日 星期${_weekdays[now.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final category = ArticleListPage.tabs[_tab];
    final title = _query.isNotEmpty
        ? '搜索结果'
        : category == null
        ? '为你推荐'
        : '最新文章';
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ArticleFeed(
          category: category,
          query: _query,
          header: [
            const SizedBox(height: 8),
            LargeTitle(
              title: '拾读',
              eyebrow: _eyebrow,
              trailing: const InitialAvatar(initial: 'G'),
            ),
            const SizedBox(height: 12),
            SearchField(
              hint: '搜索文章',
              controller: _search,
              onChanged: _onQueryChanged,
            ),
            const SizedBox(height: 14),
            CategoryChips(
              labels: [
                for (final c in ArticleListPage.tabs)
                  c == null ? '推荐' : categoryLabels[c]!,
              ],
              selected: _tab,
              onSelected: _selectTab,
            ),
          ],
          sectionHeader: SectionHeader(
            title: title,
            trailing: const _LevelMenu(),
          ),
        ),
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
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: GleanColors.tint,
              ),
            ),
            const Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: GleanColors.tint,
            ),
          ],
        ),
      ),
    );
  }
}
