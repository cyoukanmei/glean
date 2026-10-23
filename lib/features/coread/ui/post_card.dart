import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../../core/design/glean_colors.dart';
import '../../../core/design/glean_theme.dart';
import '../../../core/design/ios_widgets.dart';
import '../../articles/data/article_repository.dart';
import '../../articles/ui/cover_hero.dart';
import '../../articles/ui/labels.dart';
import '../data/coread_store.dart';

String timeAgo(int epochMs, DateTime now) {
  final d = now.difference(DateTime.fromMillisecondsSinceEpoch(epochMs));
  if (d.inMinutes < 1) return '刚刚';
  if (d.inHours < 1) return '${d.inMinutes} 分钟前';
  if (d.inHours < 24) return '${d.inHours} 小时前';
  if (d.inDays < 2) return '昨天';
  return '${d.inDays} 天前';
}

const _avatarColors = [
  [Color(0xFFFDE68A), Color(0xFFF59E0B)],
  [Color(0xFFC4B5FD), Color(0xFF7C3AED)],
  [Color(0xFF99F6E4), Color(0xFF0F766E)],
  [Color(0xFFFBCFE8), Color(0xFFDB2777)],
  [Color(0xFFBAE6FD), Color(0xFF0284C7)],
];

/// A gradient picked from the name, so a person keeps their colour.
List<Color> avatarColorsFor(String name) =>
    _avatarColors[name.codeUnits.fold(0, (s, c) => s + c) %
        _avatarColors.length];

class NameAvatar extends StatelessWidget {
  const NameAvatar({super.key, required this.name, this.size = 34});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => InitialAvatar(
    initial: name.characters.first.toUpperCase(),
    size: size,
    colors: avatarColorsFor(name),
  );
}

/// One shared quote: who and when, the English sentence, the thought, the
/// article it came from, likes and comments. In the feed it also previews
/// the top two comments and a "说点什么" field that opens the detail page.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.article,
    required this.liked,
    required this.commentCount,
    required this.onLike,
    required this.onOpenArticle,
    required this.surface,
    this.preview = const [],
    this.onComments,
    this.onSay,
  });

  final CoreadPost post;
  final ArticleSummary? article;
  final bool liked;
  final int commentCount;
  final VoidCallback onLike;
  final VoidCallback onOpenArticle;

  /// Hero surface of the article cover.
  final String surface;

  /// Top comments shown under the post (feed only).
  final List<CoreadComment> preview;

  /// Opens the post's comments; null on the detail page itself.
  final VoidCallback? onComments;

  /// Opens the comments with the keyboard up.
  final VoidCallback? onSay;

  @override
  Widget build(BuildContext context) {
    final a = article;
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GleanColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: GleanColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NameAvatar(name: post.author),
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
              onTap: onOpenArticle,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: GleanColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 33,
                      height: 44,
                      child: CoverHero(
                        article: a,
                        surface: '$surface-${post.id}',
                        borderRadius: 5,
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
                    Heart(liked: liked),
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
              GestureDetector(
                key: Key('comments-${post.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: onComments,
                child: Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 17,
                      color: GleanColors.label2,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$commentCount',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: GleanColors.label2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onComments,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: GleanColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final c in preview)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${c.author}：',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: GleanColors.label,
                                ),
                              ),
                              if (c.replyTo case final r?)
                                TextSpan(
                                  text: '回复 $r ',
                                  style: TextStyle(color: GleanColors.label2),
                                ),
                              TextSpan(text: c.text),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.5,
                            color: GleanColors.ink2,
                          ),
                        ),
                      ),
                    if (commentCount > preview.length)
                      Text(
                        '查看全部 $commentCount 条评论',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: GleanColors.tint,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (onSay != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              key: Key('say-${post.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: onSay,
              child: Container(
                height: 36,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: GleanColors.background,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  '说点什么…',
                  style: TextStyle(fontSize: 13.5, color: GleanColors.label3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return onComments == null
        ? card
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onComments,
            child: card,
          );
  }
}

/// Heart that squashes and pops (like the collect bookmark) when liked.
class Heart extends StatelessWidget {
  const Heart({super.key, required this.liked, this.size = 18});

  final bool liked;
  final double size;

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
        size: size,
        color: liked ? GleanColors.red : GleanColors.label2,
      ),
    );
  }
}

/// A new item opens up its space and fades in.
class GrowIn extends StatelessWidget {
  const GrowIn({super.key, required this.child});

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
