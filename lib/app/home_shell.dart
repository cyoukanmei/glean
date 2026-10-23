import 'package:flutter/material.dart';

import '../core/analytics/analytics.dart';
import '../core/design/glean_colors.dart';
import '../core/design/ios_widgets.dart';
import '../core/widgets/state_illustration.dart';
import '../features/articles/ui/article_list_page.dart';
import '../features/vocab/ui/vocab_page.dart';

/// Bottom navigation: 首页 / 共读 / 生词本 / 我的.
///
/// An IndexedStack keeps every tab alive, so switching back restores its
/// scroll position and loaded pages. The bar is frosted glass and the body
/// extends under it (Scaffold adds its height to the body's bottom padding,
/// which the pages' scroll views respect). The reader is pushed on the root
/// navigator above this shell, which hides the bar while reading.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _tabs = [
    (Icons.auto_stories_outlined, Icons.auto_stories_rounded, '首页', 'home'),
    (Icons.forum_outlined, Icons.forum_rounded, '共读', 'coread'),
    (Icons.bookmarks_outlined, Icons.bookmarks_rounded, '生词本', 'vocab'),
    (Icons.person_outline_rounded, Icons.person_rounded, '我的', 'me'),
  ];

  int _index = 0;

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    Analytics.track('page_view', {'page': _tabs[i].$4});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: const [
          ArticleListPage(),
          _ComingSoon(
            title: '共读',
            illustration: StateIllustration.reading,
            headline: '和书友一起读',
            hint: '中英读后分享，即将上线',
            width: 300,
          ),
          VocabPage(),
          _ComingSoon(
            title: '我的',
            illustration: StateIllustration.readingComplete,
            headline: '阅读统计与设置',
            hint: '即将上线',
          ),
        ],
      ),
      bottomNavigationBar: _GlassTabBar(
        index: _index,
        tabs: [for (final t in _tabs) (t.$1, t.$2, t.$3)],
        onSelect: _select,
      ),
    );
  }
}

class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({
    required this.index,
    required this.tabs,
    required this.onSelect,
  });

  final int index;
  final List<(IconData, IconData, String)> tabs;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Glass(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: GleanColors.separator, width: 0.5),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: 6, bottom: bottom > 0 ? bottom : 8),
          child: Row(
            children: [
              for (final (i, (icon, selectedIcon, label)) in tabs.indexed)
                Expanded(
                  child: _TabItem(
                    icon: i == index ? selectedIcon : icon,
                    label: label,
                    selected: i == index,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? GleanColors.tint : const Color(0xFF8E8E93);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A small pop when a tab becomes selected.
          TweenAnimationBuilder<double>(
            key: ValueKey(selected),
            tween: Tween(begin: selected ? 0.85 : 1, end: 1),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            builder: (context, s, child) =>
                Transform.scale(scale: s, child: child),
            child: Icon(icon, size: 26, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Temporary stand-in until the tab's feature lands.
class _ComingSoon extends StatelessWidget {
  const _ComingSoon({
    required this.title,
    required this.illustration,
    required this.headline,
    required this.hint,
    this.width = 200,
  });

  final String title;
  final String illustration;
  final String headline;
  final String hint;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LargeTitle(title: title),
            Expanded(
              child: Center(
                child: StateIllustration(
                  asset: illustration,
                  title: headline,
                  message: hint,
                  width: width,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
