import 'package:flutter/material.dart';

import '../../../core/widgets/shimmer.dart';
import '../data/article_repository.dart';
import 'cover_hero.dart';
import 'labels.dart';

class ArticleCard extends StatelessWidget {
  const ArticleCard({
    super.key,
    required this.article,
    required this.surface,
    required this.onTap,
  });

  static const coverSize = 84.0;

  final ArticleSummary article;
  final String surface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox.square(
              dimension: coverSize,
              child: CoverHero(
                article: article,
                surface: surface,
                borderRadius: CoverHero.listRadius,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    article.summary,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    articleMeta(
                      article.category,
                      article.level,
                      article.wordCount,
                    ),
                    style: theme.textTheme.labelSmall,
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

/// Placeholder list with the same geometry as [ArticleCard], so content
/// replaces it without the layout jumping.
class ArticleListSkeleton extends StatelessWidget {
  const ArticleListSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: count,
        itemBuilder: (context, i) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    SkeletonBox(height: 18),
                    SizedBox(height: 8),
                    SkeletonBox(width: 180, height: 18),
                    SizedBox(height: 10),
                    SkeletonBox(height: 12),
                    SizedBox(height: 6),
                    SkeletonBox(width: 120, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
