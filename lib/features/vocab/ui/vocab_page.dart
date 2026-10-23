import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/widgets/state_illustration.dart';
import '../../reader/ui/open_reader.dart';
import '../data/vocab_repository.dart';

/// 生词本: saved words, newest first. Swipe left to delete (with undo); tap
/// to open the source article at the word.
class VocabPage extends ConsumerStatefulWidget {
  const VocabPage({super.key});

  static const surface = 'vocab';

  @override
  ConsumerState<VocabPage> createState() => _VocabPageState();
}

class _VocabPageState extends ConsumerState<VocabPage> {
  List<VocabItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await ref
        .read(vocabRepositoryProvider)
        .list(ref.read(currentUserIdProvider));
    if (mounted) setState(() => _items = items);
  }

  Future<void> _delete(VocabItem item) async {
    final repo = ref.read(vocabRepositoryProvider);
    final revision = ref.read(vocabRevisionProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    // Drop it from the list right away so Dismissible's slide-out is final.
    setState(() => _items = [...?_items]..remove(item));
    await repo.delete(item.id);
    Analytics.track('word_delete', {
      'lemma': item.lemma,
      'surface': VocabPage.surface,
    });
    revision.bump();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已删除「${item.word}」'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () async {
              await repo.restore(item.id);
              revision.bump();
            },
          ),
        ),
      );
  }

  Future<void> _open(VocabItem item) async {
    final article = await ref
        .read(articleRepositoryProvider)
        .byId(item.source.articleId);
    if (article == null || !mounted) return;
    openReader(context, article, VocabPage.surface, jumpTo: item.source);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(vocabRevisionProvider, (_, _) => _load());
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          items == null || items.isEmpty ? '生词本' : '生词本 · ${items.length}',
        ),
      ),
      body: items == null
          ? const SizedBox.expand()
          : items.isEmpty
          ? const Center(
              child: StateIllustration(
                asset: StateIllustration.emptyVocabulary,
                title: '还没有收藏生词',
                message: '阅读时长按单词，就能查释义并收藏',
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = items[i];
                return Dismissible(
                  key: ValueKey(item.id),
                  direction: DismissDirection.endToStart,
                  background: const _DeleteBackground(),
                  onDismissed: (_) {
                    HapticFeedback.mediumImpact();
                    _delete(item);
                  },
                  child: _VocabTile(item: item, onTap: () => _open(item)),
                );
              },
            ),
    );
  }
}

class _VocabTile extends StatelessWidget {
  const _VocabTile({required this.item, required this.onTap});

  final VocabItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showLemma = item.lemma != item.word.toLowerCase();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Text(item.word, style: theme.textTheme.titleMedium),
                if (showLemma)
                  Text(item.lemma, style: theme.textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.definition.split('\n').first,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            if (item.source.sentence case final s?) ...[
              const SizedBox(height: 6),
              _Sentence(sentence: s, word: item.word),
            ],
            if (item.articleTitle case final title?) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '来自《$title》',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The source sentence with the saved word in bold.
class _Sentence extends StatelessWidget {
  const _Sentence({required this.sentence, required this.word});

  final String sentence;
  final String word;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic);
    final i = sentence.indexOf(word);
    return Text.rich(
      i < 0
          ? TextSpan(text: sentence)
          : TextSpan(
              children: [
                TextSpan(text: sentence.substring(0, i)),
                TextSpan(
                  text: word,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: sentence.substring(i + word.length)),
              ],
            ),
      style: style,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.errorContainer,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 24),
          child: Icon(
            Icons.delete_outline_rounded,
            color: scheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}
