import 'package:flutter/material.dart';

import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import '../data/article_repository.dart';
import 'cover_hero.dart';
import 'labels.dart';

/// A book on a shelf grid: a 3:4 cover with a soft drop shadow and a spine
/// shade. On the cover: the category (coloured tag, top left), a gold star
/// when starred (top right), and over a bottom scrim the level with a
/// progress badge (75%, 读完). Under it the title and a meta line: reading
/// time and the author (classics) or how many people read it.
class BookTile extends StatelessWidget {
  const BookTile({
    super.key,
    required this.article,
    required this.surface,
    required this.onTap,
    this.onLongPress,
    this.badge,
    this.badgeAccent = false,
    this.starred = false,
    this.meta,
  });

  final ArticleSummary article;
  final String surface;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Bottom-right label on the cover ("75%", "读完").
  final String? badge;

  /// Badge in the brand colour (finished) instead of a dark glass.
  final bool badgeAccent;
  final bool starred;

  /// Defaults to "3 分钟 · 5215 人在读" (author instead for classics).
  final String? meta;

  static const radius = 6.0;

  /// Tag colour per category.
  static const categoryColors = {
    'classic': Color(0xFF8C2F39),
    'tech': Color(0xFF2F6FB5),
    'business': Color(0xFFB7791F),
    'culture': Color(0xFF7A4FB0),
    'daily': Color(0xFF2E8A62),
  };

  /// Height of the text under the cover, for grids' main-axis extent.
  static double textHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(56);

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x403C280A),
                    blurRadius: 14,
                    offset: Offset(0, 8),
                    spreadRadius: -6,
                  ),
                ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CoverHero(
                    article: article,
                    surface: surface,
                    borderRadius: radius,
                  ),
                  // Spine: a darker strip on the left edge.
                  const Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 6,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.horizontal(
                            left: Radius.circular(radius),
                          ),
                          gradient: LinearGradient(
                            colors: [Color(0x40000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Bottom scrim so the white text reads on any picture.
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 40,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(radius),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0x99000000)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 7,
                    child: Container(
                      key: const Key('book-category'),
                      padding: const EdgeInsets.fromLTRB(5, 1.5, 6, 1.5),
                      decoration: BoxDecoration(
                        color:
                            categoryColors[article.category] ??
                            GleanColors.tint,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(6),
                        ),
                      ),
                      child: Text(
                        categoryLabels[article.category] ?? article.category,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    bottom: 5,
                    right: badge == null ? 6 : 44,
                    child: Text(
                      levelLabels[article.level] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Color(0x66000000), blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                  if (starred)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        key: const Key('book-star'),
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: GleanColors.gold,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.star_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (badge case final text?)
                    Positioned(
                      right: 5,
                      bottom: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: badgeAccent
                              ? GleanColors.tint
                              : const Color(0x99000000),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          text,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            article.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: GleanColors.label,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            meta ??
                [
                  '${readingMinutes(article.wordCount)} 分钟',
                  if (article.author case final a?)
                    a
                  else if (article.readers > 0)
                    '${compactCount(article.readers)} 人在读',
                ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: GleanColors.label2),
          ),
        ],
      ),
    );
  }
}
