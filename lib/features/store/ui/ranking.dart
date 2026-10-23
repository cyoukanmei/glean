import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import '../../../core/design/tabs.dart';
import '../../../core/navigation/swipe_back_route.dart';
import '../../articles/data/article_repository.dart';
import '../../articles/ui/cover_hero.dart';
import '../../articles/ui/labels.dart';
import '../../reader/ui/open_reader.dart';

/// The number a board ranks by, as shown under a title.
String rankStat(RankBoard board, ArticleSummary a) => switch (board) {
  RankBoard.reading => '${compactCount(a.readers)} 在读',
  RankBoard.favorites => '${compactCount(a.favorites)} 收藏',
  RankBoard.newest =>
    '${categoryLabels[a.category] ?? a.category} · '
        '${levelLabels[a.level] ?? ''}',
};

/// Gold / orange / amber for the top three, grey after.
Color rankColor(int rank) => switch (rank) {
  1 => const Color(0xFFD9534A),
  2 => const Color(0xFFE08A2E),
  3 => const Color(0xFFC8A02E),
  _ => GleanColors.label3,
};

void openRanking(BuildContext context, RankBoard board) =>
    Navigator.of(context).push(
      SwipeBackPageRoute<void>(
        settings: RouteSettings(name: '/store/ranking/${board.name}'),
        builder: (_) => RankingPage(initial: board),
      ),
    );

/// 书城's ranking card: 热读榜 / 收藏榜 / 新书榜 tabs over the top six in two
/// columns (1-3 left, 4-6 right), "完整榜单" opens [RankingPage].
class RankingCard extends ConsumerStatefulWidget {
  const RankingCard({super.key});

  @override
  ConsumerState<RankingCard> createState() => _RankingCardState();
}

class _RankingCardState extends ConsumerState<RankingCard> {
  RankBoard _board = RankBoard.reading;
  Map<RankBoard, List<ArticleSummary>> _boards = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(articleRepositoryProvider);
    final lists = await Future.wait([
      for (final b in RankBoard.values) repo.ranking(b, limit: 6),
    ]);
    if (!mounted) return;
    setState(
      () => _boards = {for (final b in RankBoard.values) b: lists[b.index]},
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(feedRevisionProvider, (_, _) => _load());
    final items = _boards[_board] ?? const [];
    final surface = 'rank-card-${_board.name}';
    Widget item(int i) => i < items.length
        ? _RankRow(
            key: ValueKey('$surface-${items[i].id}'),
            rank: i + 1,
            article: items[i],
            stat: rankStat(_board, items[i]),
            surface: surface,
          )
        : const SizedBox(height: _RankRow.coverHeight);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      decoration: BoxDecoration(
        color: GleanColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: GleanColors.cardShadow,
      ),
      child: Column(
        children: [
          TextTabs(
            key: const Key('rank-tabs'),
            labels: [for (final b in RankBoard.values) b.label],
            selected: _board.index,
            fontSize: 14.5,
            gap: 18,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            onSelected: (i) {
              setState(() => _board = RankBoard.values[i]);
              Analytics.track('rank_switch', {'board': _board.name});
            },
            trailing: GestureDetector(
              key: const Key('rank-more'),
              behavior: HitTestBehavior.opaque,
              onTap: () => openRanking(context, _board),
              child: Row(
                children: [
                  Text(
                    '完整榜单',
                    style: TextStyle(fontSize: 12.5, color: GleanColors.label2),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: GleanColors.label2,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(a),
                child: child,
              ),
            ),
            child: Padding(
              key: ValueKey(_board),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final col in [0, 3]) ...[
                    if (col > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        children: [for (var i = col; i < col + 3; i++) item(i)],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    super.key,
    required this.rank,
    required this.article,
    required this.stat,
    required this.surface,
  });

  final int rank;
  final ArticleSummary article;
  final String stat;
  final String surface;

  static const coverHeight = 68.0;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: () => openReader(context, article, surface),
      child: SizedBox(
        height: coverHeight,
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  fontStyle: FontStyle.italic,
                  color: rankColor(rank),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 39,
              height: 52,
              child: CoverHero(
                article: article,
                surface: surface,
                borderRadius: 5,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: GleanColors.label,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    stat,
                    maxLines: 1,
                    style: TextStyle(fontSize: 11, color: GleanColors.label2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full ranking: the top 20 of each board, switchable.
class RankingPage extends ConsumerStatefulWidget {
  const RankingPage({super.key, this.initial = RankBoard.reading});

  final RankBoard initial;

  @override
  ConsumerState<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends ConsumerState<RankingPage> {
  late RankBoard _board = widget.initial;
  final Map<RankBoard, List<ArticleSummary>> _boards = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final board = _board;
    if (_boards.containsKey(board)) return;
    final items = await ref.read(articleRepositoryProvider).ranking(board);
    if (mounted) setState(() => _boards[board] = items);
  }

  @override
  Widget build(BuildContext context) {
    final items = _boards[_board];
    final surface = 'rank-page-${_board.name}';
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(
        title: const Text('排行榜'),
        backgroundColor: GleanColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          TextTabs(
            labels: [for (final b in RankBoard.values) b.label],
            selected: _board.index,
            onSelected: (i) {
              setState(() => _board = RankBoard.values[i]);
              _load();
              Analytics.track('rank_switch', {'board': _board.name});
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: items == null
                  ? const SizedBox.expand()
                  : ListView.builder(
                      key: ValueKey(_board),
                      padding: EdgeInsets.fromLTRB(16, 4, 16, bottom + 24),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final a = items[i];
                        return _RankingTile(
                          rank: i + 1,
                          article: a,
                          stat: rankStat(_board, a),
                          surface: surface,
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingTile extends StatelessWidget {
  const _RankingTile({
    required this.rank,
    required this.article,
    required this.stat,
    required this.surface,
  });

  final int rank;
  final ArticleSummary article;
  final String stat;
  final String surface;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: () => openReader(context, article, surface),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: GleanColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: GleanColors.cardShadow,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: rank <= 3 ? 22 : 18,
                  fontWeight: FontWeight.w800,
                  fontStyle: FontStyle.italic,
                  color: rankColor(rank),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 60,
              height: 80,
              child: CoverHero(
                article: article,
                surface: surface,
                borderRadius: 6,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: GleanColors.label,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    article.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: GleanColors.label2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    stat,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: GleanColors.tint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
