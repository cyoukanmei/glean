import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import '../../../core/design/tabs.dart';
import '../../../core/widgets/state_illustration.dart';
import '../../articles/data/article_repository.dart';
import '../../articles/ui/article_card.dart';
import '../../reader/data/progress_repository.dart';
import '../../reader/ui/open_reader.dart';
import '../data/marks_repository.dart';
import 'article_actions.dart';

enum LibrarySection {
  favorite('收藏'),
  later('稍后再读'),
  history('历史');

  const LibrarySection(this.label);

  final String label;

  MarkKind? get kind => switch (this) {
    favorite => MarkKind.favorite,
    later => MarkKind.later,
    history => null,
  };
}

/// One row: the article, when it was marked or last read, and progress.
typedef _Entry = (ArticleSummary article, int at, CardProgress? progress);

/// 我的书架: 收藏, 稍后再读 and reading history in one page with a segmented
/// switch. Marked articles swipe away (with undo); history is grouped by day.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, this.initial = LibrarySection.favorite});

  final LibrarySection initial;

  static const surface = 'library';

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  late LibrarySection _section = widget.initial;
  List<_Entry>? _entries;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final gen = ++_generation;
    final user = ref.read(currentUserIdProvider);
    final List<_Entry> entries;
    if (_section.kind case final kind?) {
      final marked = await ref.read(marksRepositoryProvider).list(user, kind);
      final progress = await ref
          .read(progressRepositoryProvider)
          .forArticles(user, marked.map((m) => m.$1.id));
      entries = [
        for (final (a, at) in marked)
          (
            a,
            at,
            switch (progress[a.id]) {
              (final max, final status) => CardProgress(
                maxProgress: max,
                finished: status == ReadingStatus.finished,
              ),
              null => null,
            },
          ),
      ];
    } else {
      final history = await ref.read(progressRepositoryProvider).history(user);
      entries = [
        for (final (a, p) in history)
          (
            a,
            p.lastReadAt,
            CardProgress(
              maxProgress: p.maxProgress,
              finished: p.status == ReadingStatus.finished,
            ),
          ),
      ];
    }
    if (!mounted || gen != _generation) return;
    setState(() => _entries = entries);
  }

  void _switch(LibrarySection s) {
    if (s == _section) return;
    setState(() {
      _section = s;
      _entries = null;
    });
    _load();
  }

  Future<void> _remove(ArticleSummary article) async {
    final kind = _section.kind!;
    HapticFeedback.mediumImpact();
    setState(
      () => _entries = [...?_entries]..removeWhere((e) => e.$1 == article),
    );
    await setMark(ref, article, kind, on: false, surface: LibraryPage.surface);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已移出「${kind.label}」'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => setMark(
              ref,
              article,
              kind,
              on: true,
              surface: LibraryPage.surface,
            ),
          ),
        ),
      );
  }

  static String _day(int ms) {
    final now = clock.now();
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    return '${d.month}月${d.day}日';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(marksRevisionProvider, (_, _) => _load());
    ref.listen(progressRevisionProvider, (_, _) => _load());
    final entries = _entries;
    final bottom = MediaQuery.paddingOf(context).bottom;

    final children = <Widget>[];
    if (entries != null && entries.isNotEmpty) {
      String? lastDay;
      var groupStart = 0;
      for (var i = 0; i < entries.length; i++) {
        final (article, at, progress) = entries[i];
        final history = _section == LibrarySection.history;
        final day = history ? _day(at) : null;
        if (history && day != lastDay) {
          children.add(SectionHeader(title: day!));
          lastDay = day;
          groupStart = i;
        }
        final lastInGroup =
            i == entries.length - 1 ||
            (history && _day(entries[i + 1].$2) != day);
        final row = GroupedRow(
          first: i == groupStart,
          last: lastInGroup,
          child: ArticleCard(
            article: article,
            surface: LibraryPage.surface,
            progress: progress,
            onTap: () => openReader(context, article, LibraryPage.surface),
            onLongPress: () => showArticleActions(
              context,
              ref,
              article,
              surface: LibraryPage.surface,
            ),
          ),
        );
        children.add(
          history
              ? row
              : Dismissible(
                  key: ValueKey('${_section.name}-${article.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    color: GleanColors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Text(
                      '移出',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  onDismissed: (_) => _remove(article),
                  child: row,
                ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏与历史'),
        backgroundColor: GleanColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: bottom + 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: TextTabs(
              key: const Key('library-tabs'),
              labels: [for (final s in LibrarySection.values) s.label],
              selected: _section.index,
              onSelected: (i) => _switch(LibrarySection.values[i]),
            ),
          ),
          if (entries == null)
            const SizedBox(height: 200)
          else if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Center(
                child: StateIllustration(
                  asset: StateIllustration.emptyArticles,
                  title: switch (_section) {
                    LibrarySection.favorite => '还没有收藏的文章',
                    LibrarySection.later => '没有稍后再读的文章',
                    LibrarySection.history => '还没有读过文章',
                  },
                  message: _section == LibrarySection.history
                      ? '打开任意一篇文章，就会出现在这里'
                      : '在列表里长按文章卡片，或在阅读页点星标',
                ),
              ),
            )
          else ...[
            if (_section != LibrarySection.history) const SizedBox(height: 12),
            ...children,
          ],
        ],
      ),
    );
  }
}
