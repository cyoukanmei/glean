import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../articles/data/article_repository.dart';
import '../../articles/ui/cover_hero.dart';
import '../../articles/ui/labels.dart';
import 'open_reader.dart';

/// "Continue reading" card at the top of 推荐: the most recently read
/// unfinished article, with a progress bar that glides to the saved value.
///
/// Reloads whenever the reader flushes progress, so coming back from an
/// article pushes the bar forward to where the reader just stopped.
class ContinueReadingCard extends ConsumerStatefulWidget {
  const ContinueReadingCard({super.key});

  static const surface = 'continue';
  static const barGlide = Duration(milliseconds: 800);

  @override
  ConsumerState<ContinueReadingCard> createState() =>
      _ContinueReadingCardState();
}

class _ContinueReadingCardState extends ConsumerState<ContinueReadingCard> {
  (ArticleSummary, double)? _item;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = ref.read(currentUserIdProvider);
    final last = await ref
        .read(progressRepositoryProvider)
        .lastUnfinished(userId);
    final article = last == null
        ? null
        : await ref.read(articleRepositoryProvider).byId(last.$1);
    if (!mounted) return;
    setState(() {
      _item = article == null ? null : (article, last!.$2.maxProgress);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(progressRevisionProvider, (_, _) => _load());
    final item = _item;
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: item == null
          ? const SizedBox(width: double.infinity)
          : _Card(article: item.$1, progress: item.$2),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.article, required this.progress});

  final ArticleSummary article;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              openReader(context, article, ContinueReadingCard.surface),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 64,
                  child: CoverHero(
                    article: article,
                    surface: ContinueReadingCard.surface,
                    borderRadius: CoverHero.listRadius,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '继续阅读 · ${categoryLabels[article.category]}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        article.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      // Starts from 0 on first show, then glides between
                      // saved values on later reloads.
                      TweenAnimationBuilder<double>(
                        key: const Key('continue-progress'),
                        tween: Tween(begin: 0, end: progress),
                        duration: ContinueReadingCard.barGlide,
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: v,
                                  minHeight: 6,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '已读 ${(v * 100).round()}%',
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
