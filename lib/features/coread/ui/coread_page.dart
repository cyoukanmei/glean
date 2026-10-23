import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/glean_theme.dart';
import '../../../core/design/ios_widgets.dart';
import '../../../core/design/tabs.dart';
import '../../../core/navigation/swipe_back_route.dart';
import '../../articles/data/article_repository.dart';
import '../../auth/application/auth.dart';
import '../../reader/ui/open_reader.dart';
import '../../vocab/data/vocab_repository.dart';
import '../data/coread_store.dart';
import 'post_card.dart';
import 'post_detail_page.dart';
import 'share_quote_sheet.dart';

final coreadStoreProvider = Provider(
  (ref) => CoreadStore(
    ref.watch(prefsProvider),
    now: () => clock.now().millisecondsSinceEpoch,
  ),
);

/// Bumped when a like or comment changes on the detail page, so the feed
/// refreshes its counts.
final coreadActivityProvider = NotifierProvider<Revision, int>(Revision.new);

/// Feed tabs of 社区.
enum CoreadTab {
  popular('推荐'),
  latest('最新'),
  mine('我的');

  const CoreadTab(this.label);

  final String label;
}

/// Selected 社区 tab; 我的 → 我的动态 switches it to [CoreadTab.mine].
class CoreadTabNotifier extends Notifier<CoreadTab> {
  @override
  CoreadTab build() => CoreadTab.popular;

  void select(CoreadTab tab) => state = tab;
}

final coreadTabProvider = NotifierProvider<CoreadTabNotifier, CoreadTab>(
  CoreadTabNotifier.new,
);

/// Opens the post's article at the quoted sentence.
Future<void> openPostQuote(
  BuildContext context,
  WidgetRef ref,
  CoreadPost post,
  ArticleSummary article,
) async {
  final paragraphs = await ref
      .read(articleRepositoryProvider)
      .paragraphs(article.id);
  if (!context.mounted) return;
  final para = post.paraIndex < paragraphs.length
      ? paragraphs[post.paraIndex]
      : '';
  final at = para.indexOf(post.quote);
  openReader(
    context,
    article,
    CoreadPage.surface,
    jumpTo: at < 0
        ? null
        : WordSource(
            articleId: article.id,
            paraIndex: post.paraIndex,
            charStart: at,
            charEnd: at + post.quote.length,
            sentence: post.quote,
          ),
  );
}

/// 社区: readers' shares, each an English sentence with a Chinese thought,
/// the article it came from and the top comments. Tapping a post opens its
/// comments; tapping the article opens it at the quote.
class CoreadPage extends ConsumerStatefulWidget {
  const CoreadPage({super.key});

  static const surface = 'coread';

  @override
  ConsumerState<CoreadPage> createState() => _CoreadPageState();
}

class _CoreadPageState extends ConsumerState<CoreadPage> {
  late final CoreadStore _store = ref.read(coreadStoreProvider);
  late List<CoreadPost> _posts = _store.posts();
  late Set<String> _liked = _store.liked();
  late Map<String, int> _counts = _store.commentCounts();
  Map<String, ArticleSummary> _articles = const {};

  /// The post just shared; it grows into the list instead of popping in.
  String? _fresh;

  @override
  void initState() {
    super.initState();
    _loadArticles();
  }

  Future<void> _loadArticles() async {
    final repo = ref.read(articleRepositoryProvider);
    final ids = {for (final p in _posts) p.articleId};
    final found = await Future.wait(ids.map(repo.byId));
    if (!mounted) return;
    setState(() => _articles = {for (final a in found.nonNulls) a.id: a});
  }

  List<CoreadPost> _shown(CoreadTab tab) => switch (tab) {
    CoreadTab.latest => _posts,
    CoreadTab.popular => [..._posts]..sort((a, b) => _score(b) - _score(a)),
    CoreadTab.mine => () {
      final commented = _store.commentedPosts();
      return [
        for (final p in _posts)
          if (p.own || commented.contains(p.id)) p,
      ];
    }(),
  };

  int _score(CoreadPost p) =>
      p.likes + (_liked.contains(p.id) ? 1 : 0) + (_counts[p.id] ?? 0) * 3;

  void _toggleLike(CoreadPost post) {
    final like = !_liked.contains(post.id);
    HapticFeedback.selectionClick();
    setState(() => like ? _liked.add(post.id) : _liked.remove(post.id));
    _store.setLiked(post.id, like);
    Analytics.track('coread_like', {'post': post.id, 'like': like});
  }

  void _openPost(CoreadPost post, {bool compose = false}) {
    Navigator.of(context).push(
      SwipeBackPageRoute<void>(
        settings: RouteSettings(name: '/community/${post.id}'),
        builder: (_) => PostDetailPage(
          post: post,
          article: _articles[post.articleId],
          compose: compose,
        ),
      ),
    );
  }

  Future<void> _compose() async {
    final shared = await showModalBottomSheet<CoreadPost>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: GleanColors.card,
      builder: (_) => const _ComposeSheet(),
    );
    if (shared == null || !mounted) return;
    setState(() {
      _posts = _store.posts();
      _fresh = shared.id;
    });
    ref.read(coreadTabProvider.notifier).select(CoreadTab.latest);
    _loadArticles();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(coreadRevisionProvider, (_, _) {
      setState(() {
        _posts = _store.posts();
        _fresh = _posts.first.id;
      });
      ref.read(coreadTabProvider.notifier).select(CoreadTab.latest);
      _loadArticles();
    });
    ref.listen(coreadActivityProvider, (_, _) {
      setState(() {
        _liked = _store.liked();
        _counts = _store.commentCounts();
      });
    });
    final tab = ref.watch(coreadTabProvider);
    final posts = _shown(tab);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverList.list(
                  children: [
                    const SizedBox(height: 8),
                    const LargeTitle(title: '社区', eyebrow: '书友的读后分享'),
                    const SizedBox(height: 8),
                    TextTabs(
                      key: const Key('coread-tabs'),
                      labels: [for (final t in CoreadTab.values) t.label],
                      selected: tab.index,
                      onSelected: (i) => ref
                          .read(coreadTabProvider.notifier)
                          .select(CoreadTab.values[i]),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
                if (posts.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(40, 60, 40, 0),
                      child: Text(
                        '还没有你的动态。\n分享一句金句，或者去评论别人的分享吧。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.6,
                          color: GleanColors.label2,
                        ),
                      ),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: posts.length,
                    itemBuilder: (context, i) {
                      final post = posts[i];
                      final article = _articles[post.articleId];
                      final card = Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: PostCard(
                          key: ValueKey(post.id),
                          post: post,
                          article: article,
                          surface: CoreadPage.surface,
                          liked: _liked.contains(post.id),
                          commentCount: _counts[post.id] ?? 0,
                          preview: _store.comments(post.id).take(2).toList(),
                          onLike: () => _toggleLike(post),
                          onOpenArticle: () {
                            if (article != null) {
                              openPostQuote(context, ref, post, article);
                            }
                          },
                          onComments: () => _openPost(post),
                          onSay: () => _openPost(post, compose: true),
                        ),
                      );
                      return post.id == _fresh ? GrowIn(child: card) : card;
                    },
                  ),
                SliverPadding(padding: EdgeInsets.only(bottom: bottom + 88)),
              ],
            ),
          ),
          Positioned(
            right: 20,
            bottom: bottom + 16,
            child: PressableScale(
              onTap: _compose,
              child: Container(
                key: const Key('coread-share'),
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: GleanColors.tint,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: GleanColors.tintDeep.withValues(alpha: 0.5),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                      spreadRadius: -8,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_rounded, size: 19, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      '分享金句',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pick a sentence from your saved words, add a thought, share.
class _ComposeSheet extends ConsumerStatefulWidget {
  const _ComposeSheet();

  @override
  ConsumerState<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends ConsumerState<_ComposeSheet> {
  final _thought = TextEditingController();
  List<VocabItem>? _sources;
  VocabItem? _picked;

  @override
  void initState() {
    super.initState();
    ref
        .read(vocabRepositoryProvider)
        .list(ref.read(currentUserIdProvider))
        .then((items) {
          if (!mounted) return;
          final seen = <String>{};
          setState(
            () => _sources = [
              for (final i in items)
                if (i.source.sentence case final s?)
                  if (seen.add(s)) i,
            ].take(8).toList(),
          );
        });
  }

  @override
  void dispose() {
    _thought.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final picked = _picked!;
    final author = ref.read(authProvider)?.name ?? '我';
    final post = await ref
        .read(coreadStoreProvider)
        .share(
          author: author,
          articleId: picked.source.articleId,
          paraIndex: picked.source.paraIndex,
          quote: picked.source.sentence!,
          thought: _thought.text.trim(),
        );
    Analytics.track('coread_share', {'article_id': post.articleId});
    if (mounted) Navigator.pop(context, post);
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '分享金句',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '从你收藏生词的原句里选一句',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: GleanColors.label2),
          ),
          const SizedBox(height: 14),
          if (sources == null)
            const SizedBox(height: 80)
          else if (sources.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text(
                '还没有可分享的句子。\n阅读时长按单词收藏，它所在的句子就会出现在这里。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: GleanColors.label2,
                ),
              ),
            )
          else ...[
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sources.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final item = sources[i];
                  final selected = item == _picked;
                  return PressableScale(
                    onTap: () => setState(() => _picked = item),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: selected
                            ? GleanColors.mintSoft
                            : GleanColors.background,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? GleanColors.tint
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        item.source.sentence!,
                        style: const TextStyle(
                          fontFamily: serifFamily,
                          fontFamilyFallback: serifFallback,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
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
              onPressed: _picked == null ? null : _share,
              child: const Text('发布'),
            ),
          ],
        ],
      ),
    );
  }
}
