import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/glean_theme.dart';
import '../../../core/design/ios_widgets.dart';
import '../../articles/data/article_repository.dart';
import '../../articles/ui/cover_hero.dart';
import '../../articles/ui/labels.dart';
import '../../auth/application/auth.dart';
import '../../reader/ui/open_reader.dart';
import '../../vocab/data/vocab_repository.dart';
import '../data/coread_store.dart';
import 'share_quote_sheet.dart';

final coreadStoreProvider = Provider(
  (ref) => CoreadStore(
    ref.watch(prefsProvider),
    now: () => clock.now().millisecondsSinceEpoch,
  ),
);

enum _Sort { popular, latest }

/// 共读: readers' shares, each an English sentence with a Chinese thought
/// and the article it came from. Tapping the article opens it at the quote.
class CoreadPage extends ConsumerStatefulWidget {
  const CoreadPage({super.key});

  static const surface = 'coread';

  @override
  ConsumerState<CoreadPage> createState() => _CoreadPageState();
}

class _CoreadPageState extends ConsumerState<CoreadPage> {
  late final CoreadStore _store = ref.read(coreadStoreProvider);
  late List<CoreadPost> _posts = _store.posts();
  late final Set<String> _liked = _store.liked();
  Map<String, ArticleSummary> _articles = const {};
  _Sort _sort = _Sort.popular;

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

  List<CoreadPost> get _sorted => switch (_sort) {
    _Sort.latest => _posts,
    _Sort.popular => [..._posts]..sort((a, b) => _score(b) - _score(a)),
  };

  int _score(CoreadPost p) =>
      p.likes + (_liked.contains(p.id) ? 1 : 0) + p.comments * 3;

  void _toggleLike(CoreadPost post) {
    final like = !_liked.contains(post.id);
    HapticFeedback.selectionClick();
    setState(() => like ? _liked.add(post.id) : _liked.remove(post.id));
    _store.setLiked(post.id, like);
    Analytics.track('coread_like', {'post': post.id, 'like': like});
  }

  Future<void> _openQuote(CoreadPost post) async {
    final article = _articles[post.articleId];
    if (article == null) return;
    final paragraphs = await ref
        .read(articleRepositoryProvider)
        .paragraphs(article.id);
    if (!mounted) return;
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

  Future<void> _compose() async {
    final shared = await showModalBottomSheet<CoreadPost>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: GleanColors.sheet,
      builder: (_) => const _ComposeSheet(),
    );
    if (shared == null || !mounted) return;
    setState(() {
      _posts = _store.posts();
      _sort = _Sort.latest;
      _fresh = shared.id;
    });
    _loadArticles();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(coreadRevisionProvider, (_, _) {
      setState(() {
        _posts = _store.posts();
        _sort = _Sort.latest;
        _fresh = _posts.first.id;
      });
      _loadArticles();
    });
    final posts = _sorted;
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
                    const LargeTitle(title: '共读', eyebrow: '书友的读后分享'),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: 200,
                          child: IosSegmented<_Sort>(
                            value: _sort,
                            items: const {
                              _Sort.popular: '推荐',
                              _Sort.latest: '最新',
                            },
                            onChanged: (s) => setState(() => _sort = s),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SliverList.builder(
                  itemCount: posts.length,
                  itemBuilder: (context, i) {
                    final post = posts[i];
                    final card = _PostCard(
                      key: ValueKey(post.id),
                      post: post,
                      article: _articles[post.articleId],
                      liked: _liked.contains(post.id),
                      onLike: () => _toggleLike(post),
                      onOpen: () => _openQuote(post),
                    );
                    return post.id == _fresh ? _GrowIn(child: card) : card;
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
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: GleanColors.label,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                      spreadRadius: -8,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white),
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

String timeAgo(int epochMs, DateTime now) {
  final d = now.difference(DateTime.fromMillisecondsSinceEpoch(epochMs));
  if (d.inMinutes < 1) return '刚刚';
  if (d.inHours < 1) return '${d.inMinutes} 分钟前';
  if (d.inHours < 24) return '${d.inHours} 小时前';
  if (d.inDays < 2) return '昨天';
  return '${d.inDays} 天前';
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    super.key,
    required this.post,
    required this.article,
    required this.liked,
    required this.onLike,
    required this.onOpen,
  });

  final CoreadPost post;
  final ArticleSummary? article;
  final bool liked;
  final VoidCallback onLike;
  final VoidCallback onOpen;

  static const _avatarColors = [
    [Color(0xFFFDE68A), Color(0xFFF59E0B)],
    [Color(0xFFC4B5FD), Color(0xFF7C3AED)],
    [Color(0xFF99F6E4), Color(0xFF0F766E)],
    [Color(0xFFFBCFE8), Color(0xFFDB2777)],
    [Color(0xFFBAE6FD), Color(0xFF0284C7)],
  ];

  @override
  Widget build(BuildContext context) {
    final a = article;
    final colors =
        _avatarColors[post.author.codeUnits.fold(0, (s, c) => s + c) %
            _avatarColors.length];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GleanColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialAvatar(
                initial: post.author.characters.first.toUpperCase(),
                size: 34,
                colors: colors,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.author,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${a == null ? '分享了一句' : '读完《${a.title}》'}'
                      ' · ${timeAgo(post.createdAt, clock.now())}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: GleanColors.label2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: GleanColors.tintBright, width: 3),
              ),
            ),
            child: Text(
              '“${post.quote}”',
              style: TextStyle(
                fontFamily: serifFamily,
                fontFamilyFallback: serifFallback,
                fontSize: 18,
                height: 1.5,
                color: GleanColors.label,
              ),
            ),
          ),
          if (post.thought.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              post.thought,
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: GleanColors.ink2,
              ),
            ),
          ],
          if (a != null) ...[
            const SizedBox(height: 12),
            PressableScale(
              onTap: onOpen,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: GleanColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 40,
                      child: CoverHero(
                        article: a,
                        surface: '${CoreadPage.surface}-${post.id}',
                        borderRadius: 9,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            articleMeta(a.category, a.level, a.wordCount),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: GleanColors.label2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: GleanColors.label3,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              GestureDetector(
                key: Key('like-${post.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: onLike,
                child: Row(
                  children: [
                    _Heart(liked: liked),
                    const SizedBox(width: 5),
                    Text(
                      '${post.likes + (liked ? 1 : 0)}',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: liked ? GleanColors.red : GleanColors.label2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 22),
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 17,
                color: GleanColors.label2,
              ),
              const SizedBox(width: 5),
              Text(
                '${post.comments}',
                style: TextStyle(fontSize: 13.5, color: GleanColors.label2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Heart that squashes and pops (like the collect bookmark) when liked.
class _Heart extends StatelessWidget {
  const _Heart({required this.liked});

  final bool liked;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(liked),
      tween: Tween(begin: liked ? 0.6 : 1, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.elasticOut,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Icon(
        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: 18,
        color: liked ? GleanColors.red : GleanColors.label2,
      ),
    );
  }
}

/// A newly shared post opens up its space and fades in.
class _GrowIn extends StatelessWidget {
  const _GrowIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: t,
          child: Opacity(opacity: t, child: child),
        ),
      ),
      child: child,
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
