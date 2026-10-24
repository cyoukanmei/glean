import 'package:flutter/material.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/design/ios_widgets.dart';
import '../../reader/ui/reader_chrome.dart';
import '../data/ai_repository.dart';

/// AI 导读 above the article: CEFR grade and a two-line summary, tapping
/// opens the full summary, key points, the grading reason and the quiz.
/// It starts collapsed at a fixed height, so restoring the saved reading
/// position is not thrown off.
class AiGuideCard extends StatefulWidget {
  const AiGuideCard({
    super.key,
    required this.articleId,
    required this.ai,
    required this.palette,
    required this.quiz,
    required this.onQuiz,
  });

  final String articleId;
  final ArticleAi ai;
  final ReaderPalette palette;

  /// The last attempt, if any.
  final QuizResult? quiz;
  final VoidCallback onQuiz;

  @override
  State<AiGuideCard> createState() => _AiGuideCardState();
}

class _AiGuideCardState extends State<AiGuideCard> {
  bool _open = false;

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      Analytics.track('ai_guide_open', {'article_id': widget.articleId});
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final ai = widget.ai;
    final bodyStyle = TextStyle(fontSize: 14.5, height: 1.6, color: p.text);
    return GestureDetector(
      key: const Key('ai-guide'),
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: p.chipBg.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.accent.withValues(alpha: 0.18)),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 16, color: p.accent),
                  const SizedBox(width: 6),
                  Text(
                    'AI 导读',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: p.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CefrBadge(cefr: ai.cefr, color: p.accent),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 280),
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: p.secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                ai.summaryZh,
                maxLines: _open ? null : 2,
                overflow: _open ? null : TextOverflow.ellipsis,
                style: bodyStyle,
              ),
              if (_open) ...[
                const SizedBox(height: 10),
                for (final point in ai.keyPoints)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 9, right: 8),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: p.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Expanded(child: Text(point, style: bodyStyle)),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  '难度 ${ai.cefr}：${ai.cefrReason}',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: p.secondary,
                  ),
                ),
                const SizedBox(height: 12),
                PressableScale(
                  key: const Key('ai-guide-quiz'),
                  onTap: widget.onQuiz,
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      switch (widget.quiz) {
                        final r? => '已答对 ${r.correct}/${r.total} · 再做一次',
                        null => '做 ${ai.questions.length} 道阅读理解题',
                      },
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.background,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '由 ${ai.model ?? 'AI'} 预先生成，仅供参考',
                  style: TextStyle(fontSize: 11, color: p.secondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// CEFR level as a small outlined tag ("B2").
class CefrBadge extends StatelessWidget {
  const CefrBadge({super.key, required this.cefr, required this.color});

  final String cefr;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        'CEFR $cefr',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: color,
        ),
      ),
    );
  }
}

/// End of the article: an invitation to check understanding.
class QuizPromptCard extends StatelessWidget {
  const QuizPromptCard({
    super.key,
    required this.count,
    required this.quiz,
    required this.palette,
    required this.onTap,
  });

  final int count;
  final QuizResult? quiz;
  final ReaderPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return PressableScale(
      key: const Key('quiz-prompt'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 28),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.chipBg.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: p.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.quiz_rounded, color: p.background, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quiz == null ? '读懂了吗？' : '阅读理解',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: p.title,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(switch (quiz) {
                    final r? => '上次答对 ${r.correct}/${r.total}，可以再做一次',
                    null => '$count 道题：主旨、细节、推断',
                  }, style: TextStyle(fontSize: 13, color: p.secondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.secondary),
          ],
        ),
      ),
    );
  }
}
