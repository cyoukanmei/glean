import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/design/glean_colors.dart';
import '../../../core/widgets/celebration.dart';
import '../../articles/data/article_repository.dart';
import '../../articles/ui/cover_hero.dart';
import '../../articles/ui/labels.dart';

/// Numbers shown on the finish card.
class FinishStats {
  const FinishStats({
    required this.activeMs,
    required this.savedWords,
    required this.finishedTotal,
    this.next,
  });

  final int activeMs;
  final int savedWords;
  final int finishedTotal;
  final ArticleSummary? next;
}

/// "读完啦": the page blurs, confetti bursts from the centre and a card pops
/// up with this read's numbers and a way straight into the next article.
class FinishOverlay extends StatefulWidget {
  const FinishOverlay({
    super.key,
    required this.stats,
    required this.onNext,
    required this.onClose,
    this.backdrop = const Color(0xFFFBF7EE),
  });

  /// The page colour the blurred page is washed with.
  final Color backdrop;

  final FinishStats stats;
  final ValueChanged<ArticleSummary> onNext;
  final VoidCallback onClose;

  static const popIn = Duration(milliseconds: 520);

  /// Hero surface of the next-article cover; the reader opened from it uses
  /// the same value, so the cover flies up into the new header.
  static const nextSurface = 'finish';

  @override
  State<FinishOverlay> createState() => _FinishOverlayState();
}

class _FinishOverlayState extends State<FinishOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: FinishOverlay.popIn,
  )..forward();
  late final Animation<double> _backdrop = _c.drive(
    CurveTween(curve: const Interval(0, 0.5, curve: Curves.easeOut)),
  );
  late final Animation<double> _card = _c.drive(
    CurveTween(curve: const Interval(0.15, 1, curve: Curves.easeOutBack)),
  );
  bool _confetti = true;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static String _duration(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: widget.onClose,
          child: AnimatedBuilder(
            animation: _backdrop,
            builder: (context, _) => BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: 6 * _backdrop.value,
                sigmaY: 6 * _backdrop.value,
              ),
              child: ColoredBox(
                color: widget.backdrop.withValues(
                  alpha: 0.55 * _backdrop.value,
                ),
              ),
            ),
          ),
        ),
        if (_confetti)
          CelebrationBurst(onDone: () => setState(() => _confetti = false)),
        Center(
          child: FadeTransition(
            opacity: _backdrop,
            child: ScaleTransition(
              scale: Tween(begin: 0.85, end: 1.0).animate(_card),
              child: Container(
                key: const Key('finish-card'),
                margin: const EdgeInsets.symmetric(horizontal: 28),
                constraints: const BoxConstraints(maxWidth: 380),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                decoration: BoxDecoration(
                  color: GleanColors.card,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 50,
                      offset: Offset(0, 20),
                      spreadRadius: -12,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [GleanColors.tintBright, GleanColors.tint],
                        ),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '读完啦',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '这是你读完的第 ${stats.finishedTotal} 篇，保持住 🔥',
                      style: TextStyle(fontSize: 14, color: GleanColors.label2),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _Stat(_duration(stats.activeMs), '本篇用时'),
                        _Stat('${stats.savedWords}', '本篇收藏生词'),
                        _Stat('${stats.finishedTotal}', '累计读完'),
                      ],
                    ),
                    if (stats.next case final next?) ...[
                      const SizedBox(height: 16),
                      _NextRow(article: next),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => widget.onNext(next),
                          child: const Text('继续阅读下一篇'),
                        ),
                      ),
                    ],
                    TextButton(
                      onPressed: widget.onClose,
                      child: Text(
                        '留在本文',
                        style: TextStyle(fontSize: 16, color: GleanColors.tint),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: GleanColors.label,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: GleanColors.label2),
          ),
        ],
      ),
    );
  }
}

class _NextRow extends StatelessWidget {
  const _NextRow({required this.article});

  final ArticleSummary article;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: GleanColors.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 48,
            child: CoverHero(
              article: article,
              surface: FinishOverlay.nextSurface,
              borderRadius: 12,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '下一篇 · ${categoryLabels[article.category]} · '
                  '${levelLabels[article.level]}',
                  style: TextStyle(fontSize: 12, color: GleanColors.label2),
                ),
                Text(
                  article.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: GleanColors.label3),
        ],
      ),
    );
  }
}
