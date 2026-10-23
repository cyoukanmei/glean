import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import '../../../core/design/progress_ring.dart';
import '../../articles/data/article_repository.dart';
import '../../articles/ui/cover_hero.dart';
import '../../articles/ui/labels.dart';
import 'open_reader.dart';

/// "Continue reading" card at the top of 推荐: the most recently read
/// unfinished article on a deep teal card, with a ring that glides to the
/// saved progress.
///
/// Reloads whenever the reader flushes progress, so coming back from an
/// article pushes the ring forward to where the reader just stopped.
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
    final wordsLeft = (article.wordCount * (1 - progress)).round();
    final remaining = wordsLeft < 40
        ? '马上读完'
        : '还剩约 ${readingMinutes(wordsLeft)} 分钟';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: PressableScale(
        onTap: () => openReader(context, article, ContinueReadingCard.surface),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                GleanColors.tint,
                Color(0xFF115E59),
                GleanColors.tintDeep,
              ],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x660F766E),
                blurRadius: 28,
                offset: Offset(0, 12),
                spreadRadius: -12,
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 64,
                child: CoverHero(
                  article: article,
                  surface: ContinueReadingCard.surface,
                  borderRadius: 14,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '继续阅读 · ${categoryLabels[article.category]}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: Color(0xBFFFFFFF),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 14,
                          color: Color(0xC7FFFFFF),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          remaining,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xC7FFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Starts from 0 on first show, then glides between saved values
              // on later reloads.
              TweenAnimationBuilder<double>(
                key: const Key('continue-progress'),
                tween: Tween(begin: 0, end: progress),
                duration: ContinueReadingCard.barGlide,
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => ProgressRing(
                  value: v,
                  color: GleanColors.mintLight,
                  trackColor: const Color(0x38FFFFFF),
                  child: Text(
                    '${(v * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 13,
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
    );
  }
}
