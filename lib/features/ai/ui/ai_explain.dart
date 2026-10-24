import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/glean_theme.dart';
import '../../../core/design/ios_widgets.dart';
import '../data/deepseek_client.dart';

/// AI 解释 in the word panel: what the word means in this very sentence,
/// with collocations and a fresh example. Answers are cached per word and
/// sentence, so a word looked up once explains itself offline afterwards.
/// Hidden when the build has no AI key and nothing is cached.
class AiExplainSection extends ConsumerStatefulWidget {
  const AiExplainSection({
    super.key,
    required this.word,
    required this.lemma,
    required this.sentence,
    this.articleTitle,
  });

  final String word;
  final String lemma;
  final String sentence;
  final String? articleTitle;

  @override
  ConsumerState<AiExplainSection> createState() => _AiExplainSectionState();
}

class _AiExplainSectionState extends ConsumerState<AiExplainSection> {
  Map<String, dynamic>? _result;
  bool _cached = false;
  bool _checked = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref
        .read(aiRepositoryProvider)
        .cachedExplanation(widget.lemma, widget.sentence)
        .then((hit) {
          if (!mounted) return;
          setState(() {
            _checked = true;
            _result = hit;
            _cached = hit != null;
          });
        });
  }

  Future<void> _ask() async {
    final client = ref.read(deepSeekClientProvider);
    if (client == null) return;
    if (!(ref.read(onlineProvider).value ?? true)) {
      setState(() => _error = '离线时无法使用 AI 解释，联网后再试');
      Analytics.track('ai_explain', {
        'lemma': widget.lemma,
        'source': 'offline',
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final watch = Stopwatch()..start();
    try {
      final result = await client.explainWord(
        word: widget.word,
        sentence: widget.sentence,
        articleTitle: widget.articleTitle,
      );
      await ref
          .read(aiRepositoryProvider)
          .saveExplanation(
            widget.lemma,
            widget.sentence,
            result,
            DeepSeekClient.model,
          );
      Analytics.track('ai_explain', {
        'lemma': widget.lemma,
        'source': 'api',
        'latency_ms': watch.elapsedMilliseconds,
      });
      if (mounted) setState(() => _result = result);
    } on AiException catch (e) {
      Analytics.track('ai_explain', {'lemma': widget.lemma, 'source': 'error'});
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAsk = ref.watch(deepSeekClientProvider) != null;
    final Widget child;
    if (!_checked || (_result == null && !canAsk)) {
      child = const SizedBox(width: double.infinity);
    } else if (_result case final r?) {
      child = _Answer(result: r, cached: _cached);
    } else {
      child = _AskButton(
        loading: _loading,
        error: _error,
        onTap: _loading ? null : _ask,
      );
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(
          key: ValueKey('${_result != null}-$_loading-$_error'),
          child: child,
        ),
      ),
    );
  }
}

class _AskButton extends StatelessWidget {
  const _AskButton({
    required this.loading,
    required this.error,
    required this.onTap,
  });

  final bool loading;
  final String? error;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PressableScale(
            key: const Key('ai-explain'),
            onTap: onTap,
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(21),
                gradient: LinearGradient(
                  colors: [
                    GleanColors.mintSoft,
                    GleanColors.goldSoft.withValues(alpha: 0.8),
                  ],
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading)
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: GleanColors.tint,
                      ),
                    )
                  else
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: GleanColors.tint,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    loading ? 'AI 正在结合上下文分析…' : 'AI 解释：它在这句里是什么意思',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: GleanColors.tint,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (error case final e?)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                e,
                key: const Key('ai-explain-error'),
                style: const TextStyle(fontSize: 13, color: GleanColors.red),
              ),
            ),
        ],
      ),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({required this.result, required this.cached});

  final Map<String, dynamic> result;
  final bool cached;

  @override
  Widget build(BuildContext context) {
    final collocations = (result['collocations'] as List? ?? const [])
        .whereType<String>()
        .toList();
    final body = TextStyle(
      fontSize: 14.5,
      height: 1.55,
      color: GleanColors.ink2,
    );
    return Container(
      key: const Key('ai-explain-result'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GleanColors.mintSoft.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 15,
                color: GleanColors.tint,
              ),
              const SizedBox(width: 6),
              Text(
                'AI 解释',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: GleanColors.tint,
                ),
              ),
              const Spacer(),
              Text(
                cached ? '已存在本机' : DeepSeekClient.model,
                style: TextStyle(fontSize: 11, color: GleanColors.label3),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            result['meaning_zh'] as String,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: GleanColors.label,
            ),
          ),
          if (result['explain_zh'] case final String e) ...[
            const SizedBox(height: 4),
            Text(e, style: body),
          ],
          if (collocations.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final c in collocations)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('· $c', style: body),
              ),
          ],
          if (result['example_en'] case final String en) ...[
            const SizedBox(height: 8),
            Text(
              en,
              style: TextStyle(
                fontFamily: serifFamily,
                fontFamilyFallback: serifFallback,
                fontStyle: FontStyle.italic,
                fontSize: 15,
                height: 1.5,
                color: GleanColors.label,
              ),
            ),
            if (result['example_zh'] case final String zh)
              Text(zh, style: body.copyWith(fontSize: 13.5)),
          ],
        ],
      ),
    );
  }
}
