import 'package:flutter/material.dart';

import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import '../../../core/widgets/shimmer.dart';
import '../data/article_repository.dart';
import 'cover_hero.dart';
import 'labels.dart';

/// Reading state shown on a card.
class CardProgress {
  const CardProgress({required this.maxProgress, required this.finished});

  final double maxProgress;
  final bool finished;
}

/// Feed row: cover, two-line title, level badge + meta, and either a thin
/// progress line (started) or "已读完" (finished). Presses scale like iOS.
class ArticleCard extends StatelessWidget {
  const ArticleCard({
    super.key,
    required this.article,
    required this.surface,
    required this.onTap,
    this.onLongPress,
    this.progress,
  });

  static const coverSize = 78.0;

  final ArticleSummary article;
  final String surface;
  final VoidCallback onTap;

  /// Long-press menu (收藏 / 稍后再读).
  final VoidCallback? onLongPress;
  final CardProgress? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final started = p != null && !p.finished && p.maxProgress > 0.02;
    return PressableScale(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            DecoratedBox(
              // On paper the cover lifts off the page a little.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(CoverHero.listRadius),
                boxShadow: GleanColors.cardShadow.isNotEmpty
                    ? const [
                        BoxShadow(
                          color: Color(0x4D3C280A),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                          spreadRadius: -4,
                        ),
                      ]
                    : null,
              ),
              child: SizedBox.square(
                dimension: coverSize,
                child: CoverHero(
                  article: article,
                  surface: surface,
                  borderRadius: CoverHero.listRadius,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      letterSpacing: -0.2,
                      color: GleanColors.label,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      LevelBadge(
                        level: article.level,
                        label: levelLabels[article.level] ?? '',
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${categoryLabels[article.category]} · '
                          '${article.wordCount} 词 · '
                          '${readingMinutes(article.wordCount)} 分钟',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: GleanColors.label2,
                          ),
                        ),
                      ),
                      if (p?.finished ?? false) ...[
                        const SizedBox(width: 6),
                        Text(
                          '已读完 ✓',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: GleanColors.tint,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  _Stats(article: article),
                  if (started) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: p.maxProgress,
                        minHeight: 3,
                        backgroundColor: GleanColors.fill,
                        color: GleanColors.tint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "5215 在读 · 370 收藏".
class _Stats extends StatelessWidget {
  const _Stats({required this.article});

  final ArticleSummary article;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 11.5, color: GleanColors.label2);
    Widget stat(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: GleanColors.label3),
        const SizedBox(width: 3),
        Text(text, style: style),
      ],
    );
    return Row(
      key: const Key('article-stats'),
      children: [
        stat(Icons.people_alt_outlined, '${compactCount(article.readers)} 在读'),
        const SizedBox(width: 12),
        stat(
          Icons.star_border_rounded,
          '${compactCount(article.favorites)} 收藏',
        ),
      ],
    );
  }
}

/// Wraps one row of an article list built from separate sliver items.
///
/// Classic: one inset group (outer corners rounded, hairlines between).
/// Paper: rows straight on the page with full-width hairlines
/// (see [GleanColors.listsOnPaper]).
class GroupedRow extends StatelessWidget {
  const GroupedRow({
    super.key,
    required this.first,
    required this.last,
    required this.child,
    this.dividerIndent = 14 + ArticleCard.coverSize + 14,
    this.painted = true,
  });

  final bool first;
  final bool last;
  final Widget child;
  final double dividerIndent;

  /// False lays the row out identically but draws no background or
  /// hairline (used for the shimmer layer above the skeleton's background).
  final bool painted;

  @override
  Widget build(BuildContext context) {
    const r = Radius.circular(14);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: first ? r : Radius.zero,
          bottom: last ? r : Radius.zero,
        ),
        child: ColoredBox(
          color: painted ? GleanColors.card : Colors.transparent,
          child: Column(
            children: [
              if (!first)
                painted
                    ? Hairline(indent: dividerIndent)
                    : const SizedBox(height: 0.5),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder group with the same geometry as the cards, so content
/// replaces it without the layout jumping.
class ArticleListSkeleton extends StatelessWidget {
  const ArticleListSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    // Two identical layers: white group below, placeholder blocks above.
    // The shimmer shades every opaque pixel of its child, so it wraps only
    // the blocks; one ticker still drives the whole list.
    return Stack(
      children: [
        _rows(painted: true, blocks: false),
        Shimmer(child: _rows(painted: false, blocks: true)),
      ],
    );
  }

  Widget _rows({required bool painted, required bool blocks}) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          GroupedRow(
            first: i == 0,
            last: i == count - 1,
            painted: painted,
            child: Opacity(
              opacity: blocks ? 1 : 0,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  children: [
                    SkeletonBox(
                      width: ArticleCard.coverSize,
                      height: ArticleCard.coverSize,
                      radius: CoverHero.listRadius,
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(height: 16),
                          SizedBox(height: 8),
                          SkeletonBox(width: 160, height: 16),
                          SizedBox(height: 12),
                          SkeletonBox(width: 110, height: 11),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
