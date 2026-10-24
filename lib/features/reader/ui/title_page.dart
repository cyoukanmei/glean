import 'package:flutter/material.dart';

import '../../../core/design/glean_theme.dart';
import '../../articles/data/article_repository.dart';
import '../../articles/ui/labels.dart';
import 'reader_chrome.dart';

/// The top of an article, set like a book's title page: a small line
/// ("名著 · 第一章"), a short rule, the title centred in the serif face and
/// the author.
///
/// The reader shows it at the top of the page, and the book-opening
/// transition shows the very same widget, laid out at the screen's width
/// and scaled down onto the book's first page. So when the page has grown
/// to the screen the two are identical and nothing switches.
class ReaderTitlePage extends StatelessWidget {
  const ReaderTitlePage({
    super.key,
    required this.article,
    required this.palette,
    required this.top,
  });

  final ArticleSummary article;
  final ReaderPalette palette;

  /// Space above the first line: the status bar and the floating buttons.
  final double top;

  /// [top] for a screen with [padding] (status bar).
  static double topFor(EdgeInsets padding) => padding.top + 76;

  static String kicker(ArticleSummary a) =>
      '${categoryLabels[a.category] ?? a.category} · '
      '${a.author != null ? '第一章' : levelLabels[a.level] ?? ''}';

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Padding(
      padding: EdgeInsets.fromLTRB(28, top, 28, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kicker(article),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              color: p.accent,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 56,
            height: 1,
            child: ColoredBox(color: p.secondary.withValues(alpha: 0.35)),
          ),
          const SizedBox(height: 18),
          Text(
            article.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: serifFamily,
              fontFamilyFallback: serifFallback,
              fontSize: 30,
              height: 1.18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: p.title,
            ),
          ),
          if (article.author case final author?) ...[
            const SizedBox(height: 10),
            Text(
              author,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: serifFamily,
                fontFamilyFallback: serifFallback,
                fontStyle: FontStyle.italic,
                fontSize: 16,
                color: p.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
