import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/navigation/book_open_transition.dart';
import '../../../core/navigation/swipe_back_route.dart';
import '../../articles/ui/cover_hero.dart';
import '../../articles/data/article_repository.dart';
import '../../vocab/data/vocab_repository.dart';
import '../application/reader_settings.dart';
import 'reader_chrome.dart';
import 'reader_page.dart';
import 'title_page.dart';

/// Opens [article] in the reader. [surface] names the list the tapped card
/// lives in; the card's cover Hero uses the same value in its tag. A cover
/// visible on screen opens as a book (see [BookOpenTransition]).
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
  // Opened from a visible cover: open it as a book from there. Otherwise
  // (next / previous, banners, links) the page slides in.
  final from = replace ? null : CoverHero.rectOf(surface, article.id);
  final tag = CoverHero.tagFor(surface, article.id);
  final BookOpening? book;
  if (from == null) {
    book = null;
  } else {
    // The first page uses the reader's current theme, so the page the book
    // opens onto is the reader's own top.
    final settings = ProviderScope.containerOf(
      context,
    ).read(readerSettingsProvider);
    final palette = ReaderPalette.of(
      settings.effectiveTheme(systemDark: GleanColors.dark),
    );
    book = BookOpening(
      origin: from.$1,
      originRadius: from.$2,
      cover: (radius) => CoverHero.coverOf(article, radius),
      titlePage: ReaderTitlePage(
        article: article,
        palette: palette,
        top: ReaderTitlePage.topFor(MediaQuery.paddingOf(context)),
      ),
      paper: palette.background,
      onLifted: (lifted) {
        if (lifted) {
          CoverHero.lifted.value = tag;
        } else if (CoverHero.lifted.value == tag) {
          CoverHero.lifted.value = null;
        }
      },
    );
  }
  final route = SwipeBackPageRoute<void>(
    settings: RouteSettings(name: '/article/${article.id}'),
    builder: (_) =>
        ReaderPage(article: article, surface: surface, jumpTo: jumpTo),
    book: book,
  );
  final navigator = Navigator.of(context);
  replace ? navigator.pushReplacement(route) : navigator.push(route);
}
