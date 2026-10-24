import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/glean_theme.dart';
import '../../../core/design/ios_widgets.dart';
import '../../../core/navigation/swipe_back_route.dart';
import '../../../core/widgets/celebration.dart';
import '../../articles/data/article_repository.dart';
import '../data/ai_repository.dart';

/// Opens the comprehension quiz of [article]; [onDone] runs after a result
/// was saved (the reader refreshes its quiz prompt).
Future<void> openQuiz(
  BuildContext context,
  ArticleSummary article,
  ArticleAi ai, {
  required String surface,
  VoidCallback? onDone,
}) async {
  Analytics.track('quiz_open', {'article_id': article.id, 'surface': surface});
  await Navigator.of(context).push(
    SwipeBackPageRoute<void>(
      settings: RouteSettings(name: '/article/${article.id}/quiz'),
      builder: (_) => QuizPage(article: article, ai: ai),
    ),
  );
  onDone?.call();
}

/// 阅读理解: the article's AI-written questions one at a time. Picking an
/// option locks it: the right one turns green and pops, a wrong pick shakes
/// red, and the explanation (with the evidence in the text) fades in. Ends
/// on a score; all correct gets confetti.
class QuizPage extends ConsumerStatefulWidget {
  const QuizPage({super.key, required this.article, required this.ai});

  final ArticleSummary article;
  final ArticleAi ai;

  static const reveal = Duration(milliseconds: 260);

  @override
  ConsumerState<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends ConsumerState<QuizPage> {
  final _answers = <int>[];
  int _index = 0;
  bool _done = false;

  List<QuizQuestion> get _questions => widget.ai.questions;
  int? get _picked => _answers.length > _index ? _answers[_index] : null;

  int get _correct => [
    for (final (i, q) in _questions.indexed)
      if (i < _answers.length && _answers[i] == q.answer) 1,
  ].length;

  void _pick(int option) {
    if (_picked != null) return;
    final q = _questions[_index];
    final right = option == q.answer;
    right ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
    setState(() => _answers.add(option));
    Analytics.track('quiz_answer', {
      'article_id': widget.article.id,
      'index': _index,
      'correct': right,
    });
  }

  Future<void> _next() async {
    if (_index < _questions.length - 1) {
      setState(() => _index++);
      return;
    }
    await ref
        .read(aiRepositoryProvider)
        .saveResult(
          ref.read(currentUserIdProvider),
          widget.article.id,
          _answers,
          _questions,
        );
    Analytics.track('quiz_complete', {
      'article_id': widget.article.id,
      'correct': _correct,
      'total': _questions.length,
    });
    if (mounted) setState(() => _done = true);
  }

  void _retry() => setState(() {
    _answers.clear();
    _index = 0;
    _done = false;
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读理解'),
        backgroundColor: GleanColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
              children: [
                for (var i = 0; i < _questions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: _Segment(state: _segment(i))),
                ],
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(a),
                  child: child,
                ),
              ),
              child: _done
                  ? _Score(
                      key: const ValueKey('score'),
                      correct: _correct,
                      total: _questions.length,
                      onRetry: _retry,
                      onClose: () => Navigator.of(context).maybePop(),
                    )
                  : _QuestionView(
                      key: ValueKey(_index),
                      index: _index,
                      question: _questions[_index],
                      title: widget.article.title,
                      picked: _picked,
                      onPick: _pick,
                    ),
            ),
          ),
          if (!_done)
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, bottom + 16),
              child: AnimatedOpacity(
                opacity: _picked == null ? 0 : 1,
                duration: QuizPage.reveal,
                child: IgnorePointer(
                  ignoring: _picked == null,
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      key: const Key('quiz-next'),
                      onPressed: _next,
                      child: Text(
                        _index < _questions.length - 1 ? '下一题' : '查看结果',
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 0 = to come, 1 = current, 2 = right, 3 = wrong.
  int _segment(int i) {
    if (i < _answers.length) {
      return _answers[i] == _questions[i].answer ? 2 : 3;
    }
    return i == _index && !_done ? 1 : 0;
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.state});

  final int state;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 5,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        color: switch (state) {
          1 => GleanColors.label3,
          2 => GleanColors.tintBright,
          3 => GleanColors.red,
          _ => GleanColors.fill,
        },
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    super.key,
    required this.index,
    required this.question,
    required this.title,
    required this.picked,
    required this.onPick,
  });

  final int index;
  final QuizQuestion question;
  final String title;
  final int? picked;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final q = question;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      children: [
        Text(
          '第 ${index + 1} 题 · ${q.typeLabel}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: GleanColors.tint,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '《$title》',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: GleanColors.label2),
        ),
        const SizedBox(height: 12),
        Text(
          q.question,
          style: TextStyle(
            fontFamily: serifFamily,
            fontFamilyFallback: serifFallback,
            fontSize: 21,
            height: 1.35,
            fontWeight: FontWeight.w700,
            color: GleanColors.label,
          ),
        ),
        const SizedBox(height: 18),
        for (final (i, option) in q.options.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Option(
              key: Key('quiz-option-$i'),
              letter: String.fromCharCode(65 + i),
              text: option,
              state: picked == null
                  ? _OptionState.idle
                  : i == q.answer
                  ? _OptionState.right
                  : i == picked
                  ? _OptionState.wrong
                  : _OptionState.dimmed,
              onTap: () => onPick(i),
            ),
          ),
        AnimatedSwitcher(
          duration: QuizPage.reveal,
          child: picked == null
              ? const SizedBox(width: double.infinity)
              : Container(
                  key: const Key('quiz-explain'),
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: GleanColors.card,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: GleanColors.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        picked == q.answer
                            ? '答对了'
                            : '正确答案是 ${String.fromCharCode(65 + q.answer)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: picked == q.answer
                              ? GleanColors.tint
                              : GleanColors.red,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        q.explainZh,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.6,
                          color: GleanColors.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

enum _OptionState { idle, right, wrong, dimmed }

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.letter,
    required this.text,
    required this.state,
    required this.onTap,
  });

  final String letter;
  final String text;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color border, Color ink) = switch (state) {
      _OptionState.right => (
        GleanColors.tintBright.withValues(alpha: 0.12),
        GleanColors.tintBright,
        GleanColors.tint,
      ),
      _OptionState.wrong => (
        GleanColors.red.withValues(alpha: 0.08),
        GleanColors.red,
        GleanColors.red,
      ),
      _ => (GleanColors.card, GleanColors.separator, GleanColors.label),
    };
    final tile = AnimatedContainer(
      duration: QuizPage.reveal,
      padding: const EdgeInsets.fromLTRB(12, 13, 14, 13),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: border,
          width: state == _OptionState.idle ? 0.8 : 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: QuizPage.reveal,
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: switch (state) {
                _OptionState.right => GleanColors.tintBright,
                _OptionState.wrong => GleanColors.red,
                _ => GleanColors.fill,
              },
            ),
            child: switch (state) {
              _OptionState.right => const Icon(
                Icons.check_rounded,
                size: 17,
                color: Colors.white,
              ),
              _OptionState.wrong => const Icon(
                Icons.close_rounded,
                size: 17,
                color: Colors.white,
              ),
              _ => Text(
                letter,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: GleanColors.label2,
                ),
              ),
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: TextStyle(fontSize: 15.5, height: 1.4, color: ink),
              ),
            ),
          ),
        ],
      ),
    );
    return Opacity(
      opacity: state == _OptionState.dimmed ? 0.55 : 1,
      child: PressableScale(
        onTap: state == _OptionState.idle ? onTap : null,
        child: switch (state) {
          // The right answer pops; a wrong pick shakes.
          _OptionState.right => TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.96, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.elasticOut,
            builder: (context, s, child) =>
                Transform.scale(scale: s, child: child),
            child: tile,
          ),
          _OptionState.wrong => TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 380),
            builder: (context, t, child) => Transform.translate(
              offset: Offset(sin(t * pi * 5) * 7 * (1 - t), 0),
              child: child,
            ),
            child: tile,
          ),
          _ => tile,
        },
      ),
    );
  }
}

class _Score extends StatefulWidget {
  const _Score({
    super.key,
    required this.correct,
    required this.total,
    required this.onRetry,
    required this.onClose,
  });

  final int correct;
  final int total;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  State<_Score> createState() => _ScoreState();
}

class _ScoreState extends State<_Score> {
  late bool _confetti = widget.correct == widget.total;

  @override
  Widget build(BuildContext context) {
    final perfect = widget.correct == widget.total;
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.6, end: 1),
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeOutBack,
                  builder: (context, s, child) =>
                      Transform.scale(scale: s, child: child),
                  child: Text(
                    '${widget.correct}/${widget.total}',
                    key: const Key('quiz-score'),
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      color: perfect ? GleanColors.tint : GleanColors.label,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  perfect
                      ? '全部答对，理解得很到位'
                      : widget.correct == 0
                      ? '再读一遍原文，留意解析里提到的句子'
                      : '大体读懂了，看看错的那题的解析',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: GleanColors.label2),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    key: const Key('quiz-close'),
                    onPressed: widget.onClose,
                    child: const Text('回到文章'),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: widget.onRetry,
                  child: const Text('再做一次'),
                ),
              ],
            ),
          ),
        ),
        if (_confetti)
          CelebrationBurst(onDone: () => setState(() => _confetti = false)),
      ],
    );
  }
}
