import 'package:flutter/material.dart';

import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import '../data/article_repository.dart';
import 'cover_hero.dart';
import 'labels.dart';

/// A book on a shelf grid: a 3:4 cover with a soft drop shadow and a spine
/// shade, a corner badge (progress, 读完), a gold star when starred, then
/// the title and a short meta line.
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

  /// Defaults to "名著 · 6 分钟".
  final String? meta;

  static const radius = 6.0;

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
                  if (starred)
                    Positioned(
                      left: 6,
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
                '${categoryLabels[article.category] ?? article.category}'
                    ' · ${readingMinutes(article.wordCount)} 分钟',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: GleanColors.label2),
          ),
        ],
      ),
    );
  }
}
