import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/widgets/collect_button.dart';
import '../data/dictionary_repository.dart';
import '../data/vocab_repository.dart';

/// Bottom sheet for a long-pressed word: headword, phonetic, definition,
/// the sentence it came from, and the save toggle.
class WordSheet extends ConsumerStatefulWidget {
  const WordSheet({
    super.key,
    required this.word,
    required this.entry,
    required this.source,
  });

  /// As it appears in the text.
  final String word;

  /// Null when the dictionary has no entry; the word cannot be saved then.
  final DictEntry? entry;
  final WordSource source;

  static Future<void> show(
    BuildContext context, {
    required String word,
    required DictEntry? entry,
    required WordSource source,
  }) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => WordSheet(word: word, entry: entry, source: source),
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
    final theme = Theme.of(context);
    final entry = widget.entry;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 10,
              children: [
                Text(widget.word, style: theme.textTheme.headlineSmall),
                if (entry?.phonetic case final p?)
                  Text('/$p/', style: theme.textTheme.bodyMedium),
                if (entry != null && entry.lemma != widget.word.toLowerCase())
                  Text('原形 ${entry.lemma}', style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              entry?.definition ?? '本地词典里没有这个词',
              style: theme.textTheme.bodyLarge,
            ),
            if (widget.source.sentence case final sentence?) ...[
              const SizedBox(height: 16),
              Text('原句', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(
                sentence,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (entry != null)
              Align(
                alignment: Alignment.centerRight,
                child: CollectButton(
                  collected: _collected ?? false,
                  onPressed: _collected == null || _writing ? null : _toggle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
