import 'package:flutter/material.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/navigation/swipe_back_route.dart';
import '../../articles/data/article_repository.dart';
import 'reader_page.dart';

/// Opens [article] in the reader. [surface] names the list the tapped card
/// lives in; the card's cover Hero uses the same value in its tag.
void openReader(BuildContext context, ArticleSummary article, String surface) {
  Analytics.track('article_open', {
    'article_id': article.id,
    'surface': surface,
  });
  Navigator.of(context).push(
    SwipeBackPageRoute<void>(
      settings: RouteSettings(name: '/article/${article.id}'),
      builder: (_) => ReaderPage(article: article, surface: surface),
    ),
  );
}
