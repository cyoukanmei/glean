import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics/analytics.dart';
import '../core/design/glean_colors.dart';
import '../core/design/ios_widgets.dart';
import '../core/design/layout.dart';
import '../features/coread/ui/coread_page.dart';
import '../features/profile/ui/profile_page.dart';
import '../features/shelf/ui/shelf_page.dart';
import '../features/store/ui/store_page.dart';
import '../features/vocab/ui/vocab_page.dart';
import 'home_back_guard.dart';
import 'home_tab.dart';

/// Bottom navigation: 书架 / 书城 / 社区 / 单词本 / 我的 ([HomeTab]).
///
/// An IndexedStack keeps every tab alive, so switching back restores its
/// scroll position and loaded pages. The bar is a frosted capsule floating
/// over the content; the body extends under it (Scaffold adds its height to
/// the body's bottom padding, which the pages' scroll views respect). The
/// reader is pushed on the root navigator above this shell, which hides the
/// bar while reading. System back on the tabs goes through [HomeBackGuard].
///
/// In a wide window (the H5 build on a desktop browser) the tabs move to a
/// side bar and each page is centred at its own width ([Layout]).
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const _icons = {
    HomeTab.shelf: (Icons.auto_stories_outlined, Icons.auto_stories_rounded),
    HomeTab.store: (Icons.storefront_outlined, Icons.storefront_rounded),
    HomeTab.community: (
      CupertinoIcons.chat_bubble_2,
      CupertinoIcons.chat_bubble_2_fill,
    ),
    HomeTab.vocab: (CupertinoIcons.bookmark, CupertinoIcons.bookmark_fill),
    HomeTab.me: (CupertinoIcons.person, CupertinoIcons.person_fill),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(homeTabProvider, (_, tab) {
      Analytics.track('page_view', {'page': tab.page});
    });
    final tab = ref.watch(homeTabProvider);
    void select(int i) =>
        ref.read(homeTabProvider.notifier).go(HomeTab.values[i]);
    final tabs = [
      for (final t in HomeTab.values) (_icons[t]!.$1, _icons[t]!.$2, t.label),
    ];
    if (Layout.isWide(context)) {
      return HomeBackGuard(
        child: Scaffold(
          body: Row(
            children: [
              _SideBar(index: tab.index, tabs: tabs, onSelect: select),
              Expanded(
                child: IndexedStack(
                  index: tab.index,
                  children: const [
                    CenteredColumn(
                      maxWidth: Layout.gridMaxWidth,
                      child: ShelfPage(),
                    ),
                    CenteredColumn(
                      maxWidth: Layout.gridMaxWidth,
                      child: StorePage(),
                    ),
                    CenteredColumn(
                      maxWidth: Layout.pageMaxWidth,
                      child: CoreadPage(),
                    ),
                    CenteredColumn(
                      maxWidth: Layout.pageMaxWidth,
                      child: VocabPage(),
                    ),
                    CenteredColumn(
                      maxWidth: Layout.pageMaxWidth,
                      child: ProfilePage(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return HomeBackGuard(
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: tab.index,
          children: const [
            ShelfPage(),
            StorePage(),
            CoreadPage(),
            VocabPage(),
            ProfilePage(),
          ],
        ),
        bottomNavigationBar: _GlassTabBar(
          index: tab.index,
          tabs: tabs,
          onSelect: select,
        ),
      ),
    );
  }
}

/// The wide-window navigation: the app's name over the five tabs, the
/// selected one on the same soft teal as the tab bar's pill.
class _SideBar extends StatelessWidget {
  const _SideBar({
    required this.index,
    required this.tabs,
    required this.onSelect,
  });

  final int index;
  final List<(IconData, IconData, String)> tabs;
  final ValueChanged<int> onSelect;

  static const width = 232.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: GleanColors.card,
        border: Border(right: BorderSide(color: GleanColors.separator)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 28, 14, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 28),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.asset(
                    'assets/brand/app-icon.png',
                    width: 36,
                    height: 36,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '拾读',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: GleanColors.label,
                  ),
                ),
              ],
            ),
          ),
          for (final (i, (icon, selectedIcon, label)) in tabs.indexed)
            _SideItem(
              key: Key('side-tab-$i'),
              icon: i == index ? selectedIcon : icon,
              label: label,
              selected: i == index,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '离线优先 · 数据保存在本机',
              style: TextStyle(fontSize: 12, color: GleanColors.label3),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideItem extends StatefulWidget {
  const _SideItem({
    super.key,
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
  State<_SideItem> createState() => _SideItemState();
}

class _SideItemState extends State<_SideItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final color = selected ? GleanColors.tint : GleanColors.ink2;
    return Semantics(
      selected: selected,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: selected
                  ? GleanColors.tint.withValues(alpha: 0.12)
                  : _hover
                  ? GleanColors.fill2
                  : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 22, color: color),
                const SizedBox(width: 14),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating frosted capsule. The selected tab sits on a soft teal pill that
/// slides over with a slight overshoot; the icon fills in and pops.
class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({
    required this.index,
    required this.tabs,
    required this.onSelect,
  });

  final int index;
  final List<(IconData, IconData, String)> tabs;
  final ValueChanged<int> onSelect;

  static const height = 62.0;
  static const inset = 6.0;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottom > 0 ? bottom : 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x38000000),
              blurRadius: 30,
              offset: Offset(0, 10),
              spreadRadius: -8,
            ),
          ],
        ),
        child: Glass(
          color: GleanColors.barGlass,
          borderRadius: BorderRadius.circular(height / 2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height / 2),
              border: Border.all(color: const Color(0x0F000000), width: 0.5),
            ),
            child: SizedBox(
              height: height,
              child: LayoutBuilder(
                builder: (context, box) {
                  final itemWidth = (box.maxWidth - inset * 2) / tabs.length;
                  return Stack(
                    children: [
                      AnimatedPositioned(
                        key: const Key('tab-pill'),
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutBack,
                        left: inset + index * itemWidth,
                        top: inset,
                        bottom: inset,
                        width: itemWidth,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: GleanColors.tint.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                              (height - inset * 2) / 2,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: inset),
                        child: Row(
                          children: [
                            for (final (i, (icon, selectedIcon, label))
                                in tabs.indexed)
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
                    ],
                  );
                },
              ),
            ),
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
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // A small pop when a tab becomes selected.
            TweenAnimationBuilder<double>(
              key: ValueKey(selected),
              tween: Tween(begin: selected ? 0.8 : 1, end: 1),
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutBack,
              builder: (context, s, child) =>
                  Transform.scale(scale: s, child: child),
              child: Icon(icon, size: 23, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
