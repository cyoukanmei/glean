import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/glean_theme.dart';
import '../../../core/design/ios_widgets.dart';
import '../../../core/speech/speaker.dart';
import '../data/vocab_repository.dart';
import 'word_sheet.dart';

/// Flashcard review: the word on the front and three buttons always under
/// it. 认识 / 已掌握 rate the word and send the card off to the right;
/// 不认识 flips it (3D) to the meaning and source sentence, and 下一个 then
/// sends it off to the left. The next card rises in.
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key, required this.items});

  final List<VocabItem> items;

  static const flip = Duration(milliseconds: 450);
  static const fling = Duration(milliseconds: 320);

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage>
    with TickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: ReviewPage.flip,
  );
  late final AnimationController _fling = AnimationController(
    vsync: this,
    duration: ReviewPage.fling,
  );
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  )..forward();

  int _index = 0;
  int _direction = 1;
  final _rated = <int, int>{};

  /// The current card was rated 不认识 and shows its back.
  bool _revealed = false;

  /// Ignores taps while a card flips or flies off.
  bool _busy = false;

  @override
  void dispose() {
    _flip.dispose();
    _fling.dispose();
    _enter.dispose();
    super.dispose();
  }

  bool get _done => _index >= widget.items.length;

  Future<void> _rate(int status) async {
    if (_busy || _revealed) return;
    final item = widget.items[_index];
    _rated[status] = (_rated[status] ?? 0) + 1;
    Analytics.track('word_review', {'lemma': item.lemma, 'status': status});
    final write = ref.read(vocabRepositoryProvider).setStatus(item.id, status);
    if (status == VocabStatus.fresh) {
      // Show the meaning first; 下一个 moves on.
      HapticFeedback.selectionClick();
      setState(() {
        _revealed = true;
        _busy = true;
      });
      await _flip.forward();
      await write;
      if (mounted) setState(() => _busy = false);
      return;
    }
    HapticFeedback.lightImpact();
    await _next(direction: 1, write: write);
  }

  /// Sends the card off ([direction] 1 right, -1 left) and brings the next.
  Future<void> _next({required int direction, Future<void>? write}) async {
    if (_busy && write == null) return;
    setState(() {
      _direction = direction;
      _busy = true;
    });
    await _fling.forward(from: 0);
    await write;
    if (!mounted) return;
    setState(() {
      _index++;
      _revealed = false;
      _busy = false;
    });
    _flip.value = 0;
    _fling.value = 0;
    _enter.forward(from: 0);
    if (_done) ref.read(vocabRevisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '结束复习',
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: total == 0 ? 1 : _index / total),
                        duration: const Duration(milliseconds: 300),
                        builder: (context, v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 6,
                          color: GleanColors.tint,
                          backgroundColor: GleanColors.fill,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${min(_index + 1, total)} / $total',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: GleanColors.label2,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _done
                  ? _Summary(rated: _rated, total: total)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_fling, _enter]),
                        builder: (context, child) {
                          final f = Curves.easeIn.transform(_fling.value);
                          final e = Curves.easeOutBack.transform(_enter.value);
                          return Opacity(
                            opacity: (1 - f).clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(_direction * f * 360, f * 40),
                              child: Transform.rotate(
                                angle: _direction * f * 0.25,
                                child: Transform.scale(
                                  scale: 0.9 + 0.1 * e,
                                  child: child,
                                ),
                              ),
                            ),
                          );
                        },
                        child: AnimatedBuilder(
                          key: const Key('review-card'),
                          animation: _flip,
                          builder: (context, _) => _FlipCard(
                            t: Curves.easeInOut.transform(_flip.value),
                            item: widget.items[_index],
                          ),
                        ),
                      ),
                    ),
            ),
            if (!_done)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  height: 52,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(
                        scale: Tween(begin: 0.96, end: 1.0).animate(a),
                        child: child,
                      ),
                    ),
                    child: _revealed
                        ? _NextButton(
                            key: const Key('review-next'),
                            onTap: () => _next(direction: -1),
                          )
                        : Row(
                            key: ValueKey('rate-row-$_index'),
                            children: [
                              for (final (status, color) in const [
                                (VocabStatus.fresh, GleanColors.red),
                                (VocabStatus.known, Color(0xFF0369A1)),
                                (VocabStatus.mastered, GleanColors.green),
                              ]) ...[
                                if (status != VocabStatus.fresh)
                                  const SizedBox(width: 10),
                                Expanded(
                                  child: _RateButton(
                                    key: Key('rate-$status'),
                                    label: status == VocabStatus.fresh
                                        ? '不认识'
                                        : VocabStatus.labels[status]!,
                                    color: color,
                                    onTap: () => _rate(status),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RateButton extends StatelessWidget {
  const _RateButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// After 不认识: one wide button to move on once the meaning sank in.
class _NextButton extends StatelessWidget {
  const _NextButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: GleanColors.tint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '记住了，下一个',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _FlipCard extends ConsumerWidget {
  const _FlipCard({required this.t, required this.item});

  /// 0 = front, 1 = back.
  final double t;
  final VocabItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final angle = t * pi;
    final back = angle > pi / 2;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateY(angle),
      child: Transform(
        // The back face is drawn mirrored; undo it so its text reads.
        alignment: Alignment.center,
        transform: Matrix4.identity()..rotateY(back ? pi : 0),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: GleanColors.card,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 30,
                offset: Offset(0, 14),
                spreadRadius: -10,
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: back ? _back(context) : _front(context, ref),
        ),
      ),
    );
  }

  Widget _front(BuildContext context, WidgetRef ref) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        item.word,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: serifFamily,
          fontFamilyFallback: serifFallback,
          fontSize: 42,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
      ),
      if (item.lemma != item.word.toLowerCase())
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '原形 ${item.lemma}',
            style: TextStyle(fontSize: 15, color: GleanColors.label2),
          ),
        ),
      const SizedBox(height: 20),
      IconButton.filledTonal(
        key: const Key('review-speak'),
        onPressed: () =>
            ref.read(speakerProvider).speak(item.word, surface: 'review'),
        icon: const Icon(Icons.volume_up_rounded),
        tooltip: '发音',
      ),
      const SizedBox(height: 28),
      Text(
        '想不起来就点「不认识」看释义',
        style: TextStyle(fontSize: 13, color: GleanColors.label3),
      ),
    ],
  );

  Widget _back(BuildContext context) {
    final sentence = item.source.sentence;
    final at = sentence?.indexOf(item.word) ?? -1;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.word,
          style: const TextStyle(
            fontFamily: serifFamily,
            fontFamilyFallback: serifFallback,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        for (final (pos, text) in definitionLines(item.definition))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  if (pos != null)
                    TextSpan(
                      text: '$pos  ',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: GleanColors.tint,
                      ),
                    ),
                  TextSpan(text: text),
                ],
              ),
              style: const TextStyle(fontSize: 17, height: 1.45),
            ),
          ),
        if (sentence != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: GleanColors.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text.rich(
              TextSpan(
                children: at < 0
                    ? [TextSpan(text: sentence)]
                    : [
                        TextSpan(text: sentence.substring(0, at)),
                        TextSpan(
                          text: item.word,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: sentence.substring(at + item.word.length),
                        ),
                      ],
              ),
              style: const TextStyle(
                fontFamily: serifFamily,
                fontFamilyFallback: serifFallback,
                fontSize: 15.5,
                height: 1.55,
              ),
            ),
          ),
        ],
        if (item.articleTitle case final title?)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '出自《$title》',
              style: TextStyle(fontSize: 12.5, color: GleanColors.label2),
            ),
          ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.rated, required this.total});

  final Map<int, int> rated;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.5, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            builder: (context, s, child) =>
                Transform.scale(scale: s, child: child),
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: GleanColors.mintSoft,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 44,
                color: GleanColors.tint,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '复习完成 · $total 个',
            key: const Key('review-done'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              for (final s in [
                VocabStatus.fresh,
                VocabStatus.known,
                VocabStatus.mastered,
              ])
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${rated[s] ?? 0}',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        s == VocabStatus.fresh ? '不认识' : VocabStatus.labels[s]!,
                        style: TextStyle(
                          fontSize: 13,
                          color: GleanColors.label2,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('完成'),
            ),
          ),
        ],
      ),
    );
  }
}
