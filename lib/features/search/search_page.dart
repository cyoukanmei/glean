import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/analytics/analytics.dart';
import '../../core/design/glean_colors.dart';
import '../../core/design/glean_theme.dart';
import '../../core/design/ios_widgets.dart';
import '../articles/data/article_repository.dart';
import '../articles/ui/cover_hero.dart';
import '../articles/ui/labels.dart';
import '../reader/ui/open_reader.dart';
import '../vocab/data/vocab_repository.dart';

/// Recent searches, newest first, kept in prefs.
class SearchHistory {
  SearchHistory(this._read, this._write);

  final List<String>? Function() _read;
  final Future<void> Function(List<String>) _write;

  static const key = 'search.history';
  static const max = 10;

  List<String> get items => _read() ?? const [];

  Future<void> add(String query) {
    final q = query.trim();
    if (q.isEmpty) return Future.value();
    return _write(
      [
        q,
        ...items.where((e) => e.toLowerCase() != q.toLowerCase()),
      ].take(max).toList(),
    );
  }

  Future<void> clear() => _write(const []);
}

final searchHistoryProvider = Provider((ref) {
  final prefs = ref.watch(prefsProvider);
  return SearchHistory(
    () => prefs.getStringList(SearchHistory.key),
    (v) => prefs.setStringList(SearchHistory.key, v),
  );
});

/// [text] as spans with every case-insensitive occurrence of [needle] marked.
List<TextSpan> highlight(String text, String needle, TextStyle mark) {
  final n = needle.trim().toLowerCase();
  if (n.isEmpty) return [TextSpan(text: text)];
  final lower = text.toLowerCase();
  final spans = <TextSpan>[];
  var at = 0;
  for (var i = lower.indexOf(n); i >= 0; i = lower.indexOf(n, i + n.length)) {
    if (i > at) spans.add(TextSpan(text: text.substring(at, i)));
    spans.add(TextSpan(text: text.substring(i, i + n.length), style: mark));
    at = i + n.length;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}

/// Opens search with a cross-fade (the search field flies into place).
void openSearch(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: '/search'),
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => const SearchPage(),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
}

/// Full-text search with keyword highlight and history. A result opens the
/// article scrolled to the first match, which flashes.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  static const surface = 'search';
  static const debounce = Duration(milliseconds: 250);

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<SearchHit>? _hits;
  bool _fromHistory = false;
  int _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(SearchPage.debounce, () => _run(text));
  }

  Future<void> _run(String text, {bool fromHistory = false}) async {
    final q = text.trim();
    final gen = ++_generation;
    setState(() {
      _query = q;
      _fromHistory = fromHistory;
      if (q.isEmpty) _hits = null;
    });
    if (q.isEmpty) return;
    final hits = await ref.read(articleRepositoryProvider).search(q);
    if (!mounted || gen != _generation) return;
    setState(() => _hits = hits);
    Analytics.track('search', {
      'query': q,
      'results': hits.length,
      if (fromHistory) 'from_history': true,
    });
  }

  void _useHistory(String q) {
    _controller
      ..text = q
      ..selection = TextSelection.collapsed(offset: q.length);
    _run(q, fromHistory: true);
  }

  Future<void> _open(SearchHit hit, int position) async {
    await ref.read(searchHistoryProvider).add(_query);
    Analytics.track('search_result_open', {
      'article_id': hit.article.id,
      'position': position,
    });
    if (!mounted) return;
    final p = hit.paragraph;
    openReader(
      context,
      hit.article,
      SearchPage.surface,
      jumpTo: p == null
          ? null
          : WordSource(
              articleId: hit.article.id,
              paraIndex: p,
              charStart: hit.matchStart!,
              charEnd: hit.matchStart! + _query.length,
            ),
    );
    setState(() {}); // history changed
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Hero(
                    tag: 'search-field',
                    child: Material(
                      type: MaterialType.transparency,
                      child: SearchField(
                        key: const Key('search-input'),
                        hint: '搜索文章标题或正文',
                        controller: _controller,
                        autofocus: true,
                        onChanged: _onChanged,
                        onSubmitted: (q) {
                          _debounce?.cancel();
                          _run(q);
                          ref.read(searchHistoryProvider).add(q);
                        },
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(
                    '取消',
                    style: TextStyle(fontSize: 17, color: GleanColors.tint),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _query.isEmpty
                    ? _History(
                        key: const ValueKey('history'),
                        items: ref.read(searchHistoryProvider).items,
                        onTap: _useHistory,
                        onClear: () async {
                          await ref.read(searchHistoryProvider).clear();
                          setState(() {});
                        },
                      )
                    : hits == null
                    ? const SizedBox.expand()
                    : hits.isEmpty
                    ? Center(
                        key: const ValueKey('empty'),
                        child: Text(
                          '没有找到「$_query」',
                          style: TextStyle(
                            fontSize: 15,
                            color: GleanColors.label2,
                          ),
                        ),
                      )
                    : ListView.builder(
                        key: ValueKey('hits-$_query-$_fromHistory'),
                        padding: EdgeInsets.fromLTRB(
                          0,
                          12,
                          0,
                          MediaQuery.paddingOf(context).bottom + 16,
                        ),
                        itemCount: hits.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                              child: Text(
                                '${hits.length} 篇文章',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: GleanColors.label2,
                                ),
                              ),
                            );
                          }
                          final hit = hits[i - 1];
                          return _HitRow(
                            hit: hit,
                            query: _query,
                            first: i == 1,
                            last: i == hits.length,
                            onTap: () => _open(hit, i - 1),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({
    super.key,
    required this.items,
    required this.onTap,
    required this.onClear,
  });

  final List<String> items;
  final ValueChanged<String> onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          '可以搜标题，也可以搜正文里的任何词句',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: GleanColors.label2),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      children: [
        Row(
          children: [
            const Text(
              '搜索历史',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton(
              key: const Key('clear-history'),
              onPressed: onClear,
              child: Text('清除', style: TextStyle(color: GleanColors.label2)),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in items)
              PressableScale(
                onTap: () => onTap(q),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: GleanColors.fill,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(q, style: const TextStyle(fontSize: 14)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _HitRow extends StatelessWidget {
  const _HitRow({
    required this.hit,
    required this.query,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final SearchHit hit;
  final String query;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  static TextStyle get _mark => TextStyle(
    backgroundColor: GleanColors.tintBright.withValues(alpha: 0.25),
    color: GleanColors.tintDeep,
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) {
    final a = hit.article;
    const r = Radius.circular(14);
    final onPaper = GleanColors.listsOnPaper;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: onPaper ? 4 : 16),
      child: ClipRRect(
        borderRadius: onPaper
            ? BorderRadius.zero
            : BorderRadius.vertical(
                top: first ? r : Radius.zero,
                bottom: last ? r : Radius.zero,
              ),
        child: ColoredBox(
          color: onPaper ? GleanColors.background : GleanColors.card,
          child: Column(
            children: [
              if (!first) Hairline(indent: onPaper ? 14 : 16 + 56 + 12),
              PressableScale(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox.square(
                        dimension: 56,
                        child: CoverHero(
                          article: a,
                          surface: SearchPage.surface,
                          borderRadius: 12,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: highlight(a.title, query, _mark),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                            if (hit.snippet case final s?) ...[
                              const SizedBox(height: 4),
                              Text.rich(
                                TextSpan(children: highlight(s, query, _mark)),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: serifFamily,
                                  fontFamilyFallback: serifFallback,
                                  fontSize: 14,
                                  height: 1.45,
                                  color: GleanColors.label2,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              [
                                if (hit.count > 0) '正文 ${hit.count} 处',
                                categoryLabels[a.category] ?? a.category,
                                levelLabels[a.level] ?? '',
                              ].join(' · '),
                              style: TextStyle(
                                fontSize: 12,
                                color: GleanColors.label2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
