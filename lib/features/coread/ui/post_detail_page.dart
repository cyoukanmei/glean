import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../articles/data/article_repository.dart';
import '../../auth/application/auth.dart';
import '../data/coread_store.dart';
import 'coread_page.dart';
import 'post_card.dart';

/// One post with all its comments and a reply bar. Tapping a comment
/// replies to its author; the user's own comments come first and a new one
/// grows in at the top.
class PostDetailPage extends ConsumerStatefulWidget {
  const PostDetailPage({
    super.key,
    required this.post,
    required this.article,
    this.compose = false,
  });

  final CoreadPost post;
  final ArticleSummary? article;

  /// Opens with the keyboard up ("说点什么").
  final bool compose;

  static const surface = 'post';

  @override
  ConsumerState<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends ConsumerState<PostDetailPage> {
  late final CoreadStore _store = ref.read(coreadStoreProvider);
  late List<CoreadComment> _comments = _store.comments(widget.post.id);
  late final Set<String> _liked = _store.likedComments();
  late bool _postLiked = _store.liked().contains(widget.post.id);
  final _text = TextEditingController();
  final _focus = FocusNode();

  /// Author being replied to.
  String? _replyTo;
  String? _fresh;
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      final can = _text.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
    if (widget.compose) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _reply(CoreadComment c) {
    setState(() => _replyTo = c.own ? null : c.author);
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final c = await _store.comment(
      postId: widget.post.id,
      author: ref.read(authProvider)?.name ?? '我',
      text: text,
      replyTo: _replyTo,
    );
    Analytics.track('coread_comment', {
      'post': widget.post.id,
      if (_replyTo != null) 'reply': true,
    });
    HapticFeedback.lightImpact();
    _text.clear();
    if (!mounted) return;
    setState(() {
      _comments = _store.comments(widget.post.id);
      _fresh = c.id;
      _replyTo = null;
    });
    ref.read(coreadActivityProvider.notifier).bump();
  }

  void _togglePostLike() {
    final like = !_postLiked;
    HapticFeedback.selectionClick();
    setState(() => _postLiked = like);
    _store.setLiked(widget.post.id, like);
    Analytics.track('coread_like', {'post': widget.post.id, 'like': like});
    ref.read(coreadActivityProvider.notifier).bump();
  }

  void _toggleCommentLike(CoreadComment c) {
    final like = !_liked.contains(c.id);
    HapticFeedback.selectionClick();
    setState(() => like ? _liked.add(c.id) : _liked.remove(c.id));
    _store.setCommentLiked(c.id, like);
    Analytics.track('coread_comment_like', {'comment': c.id, 'like': like});
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    return Scaffold(
      appBar: AppBar(
        title: const Text('详情'),
        backgroundColor: GleanColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _focus.unfocus(),
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  PostCard(
                    post: widget.post,
                    article: article,
                    surface: PostDetailPage.surface,
                    liked: _postLiked,
                    commentCount: _comments.length,
                    onLike: _togglePostLike,
                    onOpenArticle: () {
                      if (article != null) {
                        openPostQuote(context, ref, widget.post, article);
                      }
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
                    child: Text(
                      '全部评论 ${_comments.length}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        '还没有评论，来说第一句吧',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: GleanColors.label2,
                        ),
                      ),
                    )
                  else
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: GleanColors.card,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: GleanColors.cardShadow,
                      ),
                      child: Column(
                        children: [
                          for (final c in _comments)
                            if (c.id == _fresh)
                              GrowIn(
                                key: ValueKey(c.id),
                                child: _CommentTile(
                                  comment: c,
                                  liked: _liked.contains(c.id),
                                  onLike: () => _toggleCommentLike(c),
                                  onReply: () => _reply(c),
                                  highlight: true,
                                ),
                              )
                            else
                              _CommentTile(
                                key: ValueKey(c.id),
                                comment: c,
                                liked: _liked.contains(c.id),
                                onLike: () => _toggleCommentLike(c),
                                onReply: () => _reply(c),
                              ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          _InputBar(
            controller: _text,
            focus: _focus,
            replyTo: _replyTo,
            canSend: _canSend,
            onCancelReply: () => setState(() => _replyTo = null),
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    super.key,
    required this.comment,
    required this.liked,
    required this.onLike,
    required this.onReply,
    this.highlight = false,
  });

  final CoreadComment comment;
  final bool liked;
  final VoidCallback onLike;
  final VoidCallback onReply;

  /// Just posted: a soft tint that fades out.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = comment;
    final tile = GestureDetector(
      key: Key('comment-${c.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onReply,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NameAvatar(name: c.author, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        c.author,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: GleanColors.label2,
                        ),
                      ),
                      if (c.own) ...[
                        const SizedBox(width: 6),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: GleanColors.mintSoft,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            child: Text(
                              '我',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: GleanColors.tint,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
                      children: [
                        if (c.replyTo case final r?) ...[
                          TextSpan(
                            text: '回复 ',
                            style: TextStyle(color: GleanColors.label2),
                          ),
                          TextSpan(
                            text: '$r：',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: GleanColors.tint,
                            ),
                          ),
                        ],
                        TextSpan(text: c.text),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: GleanColors.label,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${timeAgo(c.createdAt, clock.now())} · 回复',
                    style: TextStyle(fontSize: 12, color: GleanColors.label3),
                  ),
                ],
              ),
            ),
            GestureDetector(
              key: Key('comment-like-${c.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: onLike,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 4, 8),
                child: Column(
                  children: [
                    Heart(liked: liked, size: 17),
                    Text(
                      '${c.likes + (liked ? 1 : 0)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: liked ? GleanColors.red : GleanColors.label3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!highlight) return tile;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 1600),
      curve: Curves.easeIn,
      builder: (context, t, child) => ColoredBox(
        color: GleanColors.mintSoft.withValues(alpha: t),
        child: child,
      ),
      child: tile,
    );
  }
}

/// Text field pinned above the keyboard, with a "回复 X" chip when
/// answering someone.
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focus,
    required this.replyTo,
    required this.canSend,
    required this.onCancelReply,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String? replyTo;
  final bool canSend;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: GleanColors.card,
        border: Border(
          top: BorderSide(color: GleanColors.separator, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: replyTo == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 6),
                        child: Row(
                          children: [
                            Text(
                              '回复 $replyTo',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: GleanColors.label2,
                              ),
                            ),
                            GestureDetector(
                              onTap: onCancelReply,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 15,
                                  color: GleanColors.label3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('comment-field'),
                      controller: controller,
                      focusNode: focus,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 200,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: replyTo == null ? '说点什么…' : '回复 $replyTo',
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: GleanColors.background,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: canSend ? 1 : 0.4,
                    child: TextButton(
                      key: const Key('comment-send'),
                      onPressed: canSend ? onSend : null,
                      style: TextButton.styleFrom(
                        backgroundColor: GleanColors.tint,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: GleanColors.tint,
                        disabledForegroundColor: Colors.white,
                        minimumSize: const Size(60, 38),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text(
                        '发送',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
