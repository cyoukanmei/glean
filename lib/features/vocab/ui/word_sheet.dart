import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/glean_theme.dart';
import '../../../core/design/ios_widgets.dart';
import '../../../core/speech/speaker.dart';
import '../../../core/widgets/collect_button.dart';
import '../../coread/ui/share_quote_sheet.dart';
import '../data/dictionary_repository.dart';
import '../data/vocab_repository.dart';

/// Splits an ECDICT definition into (part of speech, meaning) lines.
///
/// "vt. 放弃, 抛弃\nn. 放任" -> [("vt.", "放弃, 抛弃"), ("n.", "放任")].
/// Domain notes such as "[计] ..." are dropped when there is anything else.
List<(String? pos, String text)> definitionLines(
  String definition, {
  int max = 3,
}) {
  final pos = RegExp(r'^([a-z]+\.)\s*(.+)$');
  final lines = [
    for (final raw in definition.split('\n'))
      if (raw.replaceAll(r'\r', '').trim() case final line when line.isNotEmpty)
        switch (pos.firstMatch(line)) {
          final m? => (m.group(1), m.group(2)!),
          null => (null, line),
        },
  ];
  final plain = lines.where((l) => !l.$2.startsWith('[')).toList();
  return (plain.isEmpty ? lines : plain).take(max).toList();
}

/// Bottom sheet for a long-pressed word: serif headword, phonetic, meanings
/// by part of speech, the sentence it came from, and the save toggle.
class WordSheet extends ConsumerStatefulWidget {
  const WordSheet({
    super.key,
    required this.word,
    required this.entry,
    required this.source,
    this.articleTitle,
  });

  /// As it appears in the text.
  final String word;

  /// Null when the dictionary has no entry; the word cannot be saved then.
  final DictEntry? entry;
  final WordSource source;
  final String? articleTitle;

  static Future<void> show(
    BuildContext context, {
    required String word,
    required DictEntry? entry,
    required WordSource source,
    String? articleTitle,
  }) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // Sized to its content (long definitions scroll) rather than capped at
    // the default 9/16 of the screen.
    isScrollControlled: true,
    backgroundColor: GleanColors.sheet,
    // Light dim: the picked word stays readable above the sheet.
    barrierColor: const Color(0x1F000000),
    builder: (_) => WordSheet(
      word: word,
      entry: entry,
      source: source,
      articleTitle: articleTitle,
    ),
  );

  @override
  ConsumerState<WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends ConsumerState<WordSheet> {
  late final String _userId = ref.read(currentUserIdProvider);
  late final VocabRepository _vocab = ref.read(vocabRepositoryProvider);
  late final Revision _revision = ref.read(vocabRevisionProvider.notifier);

  /// Null until the saved state is known.
  bool? _collected;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    if (entry != null) {
      _vocab.isCollected(_userId, entry.lemma).then((v) {
        if (mounted) setState(() => _collected = v);
      });
    }
  }

  /// Optimistic: the button flips (and bounces) at once; a failed write
  /// flips it back.
  Future<void> _toggle() async {
    final entry = widget.entry!;
    final collect = !(_collected ?? false);
    setState(() {
      _collected = collect;
      _writing = true;
    });
    try {
      if (collect) {
        await _vocab.collect(
          userId: _userId,
          word: widget.word,
          lemma: entry.lemma,
          definition: entry.definition,
          source: widget.source,
        );
      } else {
        final item = await _vocab.find(_userId, entry.lemma);
        if (item != null) await _vocab.delete(item.id);
      }
      Analytics.track(collect ? 'word_collect' : 'word_delete', {
        'lemma': entry.lemma,
        'article_id': widget.source.articleId,
        'surface': 'reader',
      });
      _revision.bump();
    } catch (e) {
      debugPrint('[vocab] write failed: $e');
      if (mounted) setState(() => _collected = !collect);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.word,
                        style: TextStyle(
                          fontFamily: serifFamily,
                          fontFamilyFallback: serifFallback,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          color: GleanColors.label,
                        ),
                      ),
                      Row(
                        children: [
                          if (entry?.phonetic case final p?) ...[
                            Text(
                              '/$p/',
                              style: TextStyle(
                                fontSize: 15,
                                color: GleanColors.label2,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          _RoundButton(
                            key: const Key('word-speak'),
                            icon: Icons.volume_up_rounded,
                            tooltip: '发音',
                            onTap: () => ref
                                .read(speakerProvider)
                                .speak(widget.word, surface: 'reader'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (entry != null && entry.lemma != widget.word.toLowerCase())
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _Chip('原形 ${entry.lemma}'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (entry == null)
              Text(
                '本地词典里没有这个词',
                style: TextStyle(fontSize: 16, color: GleanColors.label2),
              )
            else
              for (final (pos, text) in definitionLines(entry.definition))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (pos != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _Chip(pos),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          text,
                          style: const TextStyle(fontSize: 16, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
            if (widget.source.sentence case final sentence?) ...[
              const SizedBox(height: 10),
              _Quote(
                sentence: sentence,
                word: widget.word,
                title: widget.articleTitle,
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                if (entry != null)
                  Expanded(
                    child: CollectButton(
                      collected: _collected ?? false,
                      onPressed: _collected == null || _writing
                          ? null
                          : _toggle,
                    ),
                  ),
                if (widget.source.sentence != null) ...[
                  if (entry != null) const SizedBox(width: 10),
                  Tooltip(
                    message: '分享这句到共读',
                    child: PressableScale(
                      key: const Key('word-share'),
                      onTap: () => showShareQuoteSheet(
                        context,
                        source: widget.source,
                        surface: 'reader',
                      ),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: GleanColors.fill2,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.ios_share_rounded,
                          color: GleanColors.label,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.88,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: GleanColors.mintSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: GleanColors.tint),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: GleanColors.mintSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: GleanColors.tint,
          ),
        ),
      ),
    );
  }
}

/// Grey card with the source sentence, the picked word in bold.
class _Quote extends StatelessWidget {
  const _Quote({required this.sentence, required this.word, this.title});

  final String sentence;
  final String word;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final at = sentence.indexOf(word);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: GleanColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title == null ? '原句' : '原句 · $title',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: GleanColors.label2),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: at < 0
                  ? [TextSpan(text: sentence)]
                  : [
                      TextSpan(text: sentence.substring(0, at)),
                      TextSpan(
                        text: word,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: sentence.substring(at + word.length)),
                    ],
            ),
            style: TextStyle(
              fontFamily: serifFamily,
              fontFamilyFallback: serifFallback,
              fontSize: 15.5,
              height: 1.6,
              color: GleanColors.ink2,
            ),
          ),
        ],
      ),
    );
  }
}
