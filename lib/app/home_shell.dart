import 'package:flutter/material.dart';

import '../core/analytics/analytics.dart';
import '../features/articles/ui/article_list_page.dart';

/// Bottom navigation: 首页 / 共读 / 生词本 / 我的.
///
/// An IndexedStack keeps every tab alive, so switching back restores its
/// scroll position and loaded pages. The reader is pushed on the root
/// navigator above this shell, which hides the bar while reading.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _tabs = [
    (Icons.auto_stories_outlined, Icons.auto_stories, '首页', 'home'),
    (Icons.forum_outlined, Icons.forum, '共读', 'coread'),
    (Icons.bookmarks_outlined, Icons.bookmarks, '生词本', 'vocab'),
    (Icons.person_outline, Icons.person, '我的', 'me'),
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
      body: IndexedStack(
        index: _index,
        children: const [
          ArticleListPage(),
          _ComingSoon(title: '共读', hint: '书友的中英读后分享，即将上线'),
          _ComingSoon(title: '生词本', hint: '阅读时长按单词即可收藏，即将上线'),
          _ComingSoon(title: '我的', hint: '阅读统计与设置，即将上线'),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          for (final (icon, selected, label, _) in _tabs)
            NavigationDestination(
              icon: Icon(icon),
              selectedIcon: Icon(selected),
              label: label,
            ),
        ],
      ),
    );
  }
}

/// Temporary stand-in until the tab's feature lands.
class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(hint, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}
