import 'package:flutter/material.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/navigation/swipe_back_route.dart';
import '../../articles/data/article_repository.dart';
import '../../vocab/data/vocab_repository.dart';
import 'reader_page.dart';

/// Opens [article] in the reader. [surface] names the list the tapped card
/// lives in; the card's cover Hero uses the same value in its tag.
/// [jumpTo] opens at a saved word instead of the last reading position.
/// [replace] swaps out the current page (previous / next article), so back
/// still returns to the list.
void openReader(
  BuildContext context,
  ArticleSummary article,
  String surface, {
  WordSource? jumpTo,
  bool replace = false,
}) {
  Analytics.track('article_open', {
    'article_id': article.id,
    'surface': surface,
  });
  final route = SwipeBackPageRoute<void>(
    settings: RouteSettings(name: '/article/${article.id}'),
    builder: (_) =>
        ReaderPage(article: article, surface: surface, jumpTo: jumpTo),
  );
  final navigator = Navigator.of(context);
  replace ? navigator.pushReplacement(route) : navigator.push(route);
}
