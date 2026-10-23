import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../articles/data/article_repository.dart';
import '../../articles/ui/cover_hero.dart';
import '../../articles/ui/labels.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.article, required this.surface});

  /// Already loaded by the list, so the header (and the cover Hero's
  /// destination) is built on the very first frame.
  final ArticleSummary article;

  /// List the article was opened from; must match its card's Hero tag.
  final String surface;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  static const _headerHeight = 220.0;

  late final Future<List<String>> _paragraphs = ref
      .read(articleRepositoryProvider)
      .paragraphs(widget.article.id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final article = widget.article;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: _headerHeight + MediaQuery.paddingOf(context).top,
                  child: CoverHero(
                    article: article,
                    surface: widget.surface,
                    borderRadius: CoverHero.headerRadius,
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: IconButton.filledTonal(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const BackButtonIcon(),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(article.title, style: theme.textTheme.headlineSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                articleMeta(article.category, article.level, article.wordCount),
                style: theme.textTheme.labelMedium,
              ),
            ),
            FutureBuilder(
              future: _paragraphs,
              builder: (context, snap) {
                final paragraphs = snap.data ?? const <String>[];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final p in paragraphs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            p,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.6,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
