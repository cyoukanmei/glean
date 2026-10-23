import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom navigation tabs, in bar order.
enum HomeTab {
  shelf('书架', 'shelf'),
  store('书城', 'store'),
  community('社区', 'community'),
  vocab('单词本', 'vocab'),
  me('我的', 'me');

  const HomeTab(this.label, this.page);

  final String label;

  /// `page` parameter of the page_view event.
  final String page;
}

/// The selected bottom tab. Pages switch tabs through it (an empty shelf's
/// "去书城看看", 我的 → 我的动态).
class HomeTabNotifier extends Notifier<HomeTab> {
  @override
  HomeTab build() => HomeTab.shelf;

  void go(HomeTab tab) => state = tab;
}

final homeTabProvider = NotifierProvider<HomeTabNotifier, HomeTab>(
  HomeTabNotifier.new,
);
