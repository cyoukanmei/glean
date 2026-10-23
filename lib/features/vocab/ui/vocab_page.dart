import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/glean_theme.dart';
import '../../../core/design/ios_widgets.dart';
import '../../../core/widgets/state_illustration.dart';
import '../../reader/ui/open_reader.dart';
import '../data/vocab_repository.dart';
import '../../../core/navigation/swipe_back_route.dart';
import 'review_page.dart';
import 'word_sheet.dart';

/// 生词本: saved words, newest first, with search and a few counts. Swipe
/// left to delete (with undo); tap to open the source article at the word.
class VocabPage extends ConsumerStatefulWidget {
  const VocabPage({super.key});

  static const surface = 'vocab';

  @override
  ConsumerState<VocabPage> createState() => _VocabPageState();
}

class _VocabPageState extends ConsumerState<VocabPage> {
  static const _week = Duration(days: 7);

  List<VocabItem>? _items;
  String _query = '';

  /// Learning-status filter; null shows every word.
  int? _status;

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

  bool _matches(VocabItem item) {
    final q = _query.toLowerCase();
    if (_status != null && item.status != _status) return false;
    return q.isEmpty ||
        item.word.toLowerCase().contains(q) ||
        item.lemma.contains(q) ||
        item.definition.contains(q);
  }

  /// Words not mastered yet, or every word once all are mastered.
  void _review(List<VocabItem> all) {
    final due = all.where((i) => i.status < VocabStatus.mastered).toList();
    final items = (due.isEmpty ? [...all] : due)..shuffle();
    Navigator.of(context).push(
      SwipeBackPageRoute<void>(
        settings: const RouteSettings(name: '/vocab/review'),
        builder: (_) => ReviewPage(items: items.take(20).toList()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(vocabRevisionProvider, (_, _) => _load());
    final items = _items;
    final weekAgo = clock.now().subtract(_week).millisecondsSinceEpoch;
    final shown = items?.where(_matches).toList() ?? const <VocabItem>[];
    final onPaper = GleanColors.listsOnPaper;

    final Widget content;
    if (items == null) {
      content = const SliverToBoxAdapter();
    } else if (items.isEmpty) {
      content = const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 48),
          child: Center(
            child: StateIllustration(
              asset: StateIllustration.emptyVocabulary,
              title: '还没有收藏生词',
              message: '阅读时长按单词，就能查释义并收藏',
            ),
          ),
        ),
      );
    } else if (shown.isEmpty) {
      content = SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 40),
          child: Center(
            child: Text(
              '没有匹配的单词',
              style: TextStyle(fontSize: 15, color: GleanColors.label2),
            ),
          ),
        ),
      );
    } else {
      content = SliverList.builder(
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final item = shown[i];
          const r = Radius.circular(14);
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: onPaper ? 4 : 16),
            child: ClipRRect(
              borderRadius: onPaper
                  ? BorderRadius.zero
                  : BorderRadius.vertical(
                      top: i == 0 ? r : Radius.zero,
                      bottom: i == shown.length - 1 ? r : Radius.zero,
                    ),
              child: Dismissible(
                key: ValueKey(item.id),
                direction: DismissDirection.endToStart,
                background: const _DeleteBackground(),
                onDismissed: (_) {
                  HapticFeedback.mediumImpact();
                  _delete(item);
                },
                child: ColoredBox(
                  color: onPaper ? GleanColors.background : GleanColors.card,
                  child: Column(
                    children: [
                      if (i > 0) const Hairline(indent: 16),
                      _VocabTile(item: item, onTap: () => _open(item)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    final all = items ?? const <VocabItem>[];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverList.list(
              children: [
                const SizedBox(height: 8),
                LargeTitle(
                  title: '生词本',
                  eyebrow: items == null ? ' ' : '共 ${all.length} 个词',
                ),
                const SizedBox(height: 12),
                SearchField(
                  hint: '搜索单词或释义',
                  onChanged: (q) => setState(() => _query = q.trim()),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _StatTile(
                        value: all.where((i) => i.createdAt >= weekAgo).length,
                        label: '本周新增',
                      ),
                      const SizedBox(width: 10),
                      _StatTile(
                        value: all
                            .where((i) => i.status == VocabStatus.known)
                            .length,
                        label: '认识',
                      ),
                      const SizedBox(width: 10),
                      _StatTile(
                        value: all
                            .where((i) => i.status == VocabStatus.mastered)
                            .length,
                        label: '已掌握',
                        accent: true,
                      ),
                    ],
                  ),
                ),
                if (all.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ReviewButton(
                    due: all
                        .where((i) => i.status < VocabStatus.mastered)
                        .length,
                    onTap: () => _review(all),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: IosSegmented<int>(
                      value: _status ?? -1,
                      items: {-1: '全部', ...VocabStatus.labels},
                      onChanged: (s) =>
                          setState(() => _status = s < 0 ? null : s),
                    ),
                  ),
                  SectionHeader(
                    title: _query.isEmpty && _status == null
                        ? '最近收藏'
                        : '${shown.length} 个结果',
                  ),
                ],
              ],
            ),
            content,
            SliverPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewButton extends StatelessWidget {
  const _ReviewButton({required this.due, required this.onTap});

  final int due;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: PressableScale(
        key: const Key('start-review'),
        onTap: onTap,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: GleanColors.mintSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.style_rounded, color: GleanColors.tint, size: 20),
              const SizedBox(width: 8),
              Text(
                due > 0 ? '开始复习 · $due 个待复习' : '全部掌握了，再复习一遍',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: GleanColors.tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    this.accent = false,
  });

  final int value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: GleanColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(end: value.toDouble()),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text(
                '${v.round()}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: accent ? GleanColors.tint : GleanColors.label,
                ),
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: GleanColors.label2),
            ),
          ],
        ),
      ),
    );
  }
}

class _VocabTile extends StatelessWidget {
  const _VocabTile({required this.item, required this.onTap});

  final VocabItem item;
  final VoidCallback onTap;

  static Map<int, (Color, Color)> get _tags => {
    VocabStatus.fresh: (GleanColors.goldSoft, GleanColors.goldInk),
    VocabStatus.known: GleanColors.levelBadge[2]!,
    VocabStatus.mastered: GleanColors.levelBadge[1]!,
  };

  @override
  Widget build(BuildContext context) {
    final showLemma = item.lemma != item.word.toLowerCase();
    final meaning = definitionLines(
      item.definition,
      max: 2,
    ).map((l) => l.$1 == null ? l.$2 : '${l.$1} ${l.$2}').join('；');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  item.word,
                  style: TextStyle(
                    fontFamily: serifFamily,
                    fontFamilyFallback: serifFallback,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: GleanColors.label,
                  ),
                ),
                if (showLemma) ...[
                  const SizedBox(width: 8),
                  Text(
                    '原形 ${item.lemma}',
                    style: TextStyle(fontSize: 13, color: GleanColors.label2),
                  ),
                ],
                const Spacer(),
                if (_tags[item.status] case (final bg, final ink))
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      child: Text(
                        VocabStatus.labels[item.status]!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              meaning,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14.5, color: GleanColors.ink2),
            ),
            if (item.source.sentence case final s?) ...[
              const SizedBox(height: 6),
              _Sentence(sentence: s, word: item.word),
            ],
            if (item.articleTitle case final title?) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.auto_stories_rounded,
                    size: 14,
                    color: GleanColors.tint,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: GleanColors.tint,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: GleanColors.tint,
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
    final i = sentence.indexOf(word);
    return Text.rich(
      i < 0
          ? TextSpan(text: sentence)
          : TextSpan(
              children: [
                TextSpan(text: sentence.substring(0, i)),
                TextSpan(
                  text: word,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.normal,
                    color: GleanColors.label,
                  ),
                ),
                TextSpan(text: sentence.substring(i + word.length)),
              ],
            ),
      style: TextStyle(
        fontFamily: serifFamily,
        fontFamilyFallback: serifFallback,
        fontSize: 14,
        height: 1.5,
        fontStyle: FontStyle.italic,
        color: GleanColors.label2,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: GleanColors.red,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.only(right: 24),
          child: Text(
            '删除',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
