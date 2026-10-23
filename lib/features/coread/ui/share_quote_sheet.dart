import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/glean_theme.dart';
import '../../auth/application/auth.dart';
import '../../vocab/data/vocab_repository.dart';
import 'coread_page.dart';

/// Bumped when a post is shared from outside the 共读 tab, so it reloads.
final coreadRevisionProvider = NotifierProvider<Revision, int>(Revision.new);

/// Shares the sentence a word came from to 共读, with an optional thought.
/// Returns true when posted.
Future<bool> showShareQuoteSheet(
  BuildContext context, {
  required WordSource source,
  required String surface,
}) async {
  final posted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: GleanColors.sheet,
    builder: (_) => _ShareQuoteSheet(source: source, surface: surface),
  );
  if ((posted ?? false) && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已分享到共读')));
  }
  return posted ?? false;
}

class _ShareQuoteSheet extends ConsumerStatefulWidget {
  const _ShareQuoteSheet({required this.source, required this.surface});

  final WordSource source;
  final String surface;

  @override
  ConsumerState<_ShareQuoteSheet> createState() => _ShareQuoteSheetState();
}

class _ShareQuoteSheetState extends ConsumerState<_ShareQuoteSheet> {
  final _thought = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _thought.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    setState(() => _posting = true);
    final s = widget.source;
    await ref
        .read(coreadStoreProvider)
        .share(
          author: ref.read(authProvider)?.name ?? '我',
          articleId: s.articleId,
          paraIndex: s.paraIndex,
          quote: s.sentence!,
          thought: _thought.text.trim(),
        );
    Analytics.track('coread_share', {
      'article_id': s.articleId,
      'surface': widget.surface,
    });
    ref.read(coreadRevisionProvider.notifier).bump();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '分享到共读',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: GleanColors.tintBright, width: 3),
              ),
            ),
            child: Text(
              '“${widget.source.sentence}”',
              style: const TextStyle(
                fontFamily: serifFamily,
                fontFamilyFallback: serifFallback,
                fontSize: 17,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('share-thought'),
            controller: _thought,
            maxLines: 3,
            minLines: 2,
            decoration: InputDecoration(
              hintText: '写一句你的感想（可选）',
              filled: true,
              fillColor: GleanColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('share-post'),
            onPressed: _posting ? null : _post,
            child: const Text('发布'),
          ),
        ],
      ),
    );
  }
}
