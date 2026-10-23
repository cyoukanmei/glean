import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One reader's share: an English sentence from an article and their own
/// thoughts in Chinese.
class CoreadPost {
  const CoreadPost({
    required this.id,
    required this.author,
    required this.articleId,
    required this.paraIndex,
    required this.quote,
    required this.thought,
    required this.createdAt,
    this.likes = 0,
  });

  factory CoreadPost.fromJson(Map<String, dynamic> j) => CoreadPost(
    id: j['id'] as String,
    author: j['author'] as String,
    articleId: j['articleId'] as String,
    paraIndex: j['paraIndex'] as int,
    quote: j['quote'] as String,
    thought: j['thought'] as String,
    createdAt: j['createdAt'] as int,
    likes: j['likes'] as int? ?? 0,
  );

  final String id;
  final String author;
  final String articleId;

  /// Paragraph the quote comes from, so opening the article can scroll to it.
  final int paraIndex;
  final String quote;
  final String thought;
  final int createdAt;
  final int likes;

  /// Shared by the user on this device.
  bool get own => id.startsWith('u');

  Map<String, Object> toJson() => {
    'id': id,
    'author': author,
    'articleId': articleId,
    'paraIndex': paraIndex,
    'quote': quote,
    'thought': thought,
    'createdAt': createdAt,
    'likes': likes,
  };
}

/// A comment under a post; [replyTo] names the commenter it answers.
class CoreadComment {
  const CoreadComment({
    required this.id,
    required this.postId,
    required this.author,
    required this.text,
    required this.createdAt,
    this.likes = 0,
    this.replyTo,
  });

  factory CoreadComment.fromJson(Map<String, dynamic> j) => CoreadComment(
    id: j['id'] as String,
    postId: j['postId'] as String,
    author: j['author'] as String,
    text: j['text'] as String,
    createdAt: j['createdAt'] as int,
    likes: j['likes'] as int? ?? 0,
    replyTo: j['replyTo'] as String?,
  );

  final String id;
  final String postId;
  final String author;
  final String text;
  final int createdAt;
  final int likes;
  final String? replyTo;

  /// Written by the user on this device.
  bool get own => id.startsWith('uc');

  Map<String, Object?> toJson() => {
    'id': id,
    'postId': postId,
    'author': author,
    'text': text,
    'createdAt': createdAt,
    'likes': likes,
    'replyTo': replyTo,
  };
}

/// Local stand-in for a community backend: a few built-in posts and
/// comments plus the user's own shares, comments and likes, kept in shared
/// preferences.
class CoreadStore {
  CoreadStore(this._prefs, {required this._now});

  final SharedPreferences _prefs;
  final int Function() _now;

  static const _postsKey = 'coread.posts';
  static const _likedKey = 'coread.liked';
  static const _commentsKey = 'coread.comments';
  static const _commentLikedKey = 'coread.comment_liked';
  static const _minute = 60 * 1000;
  static const _hour = 3600 * 1000;

  /// Built-in posts; quotes are verbatim sentences from the seed articles.
  List<CoreadPost> _builtIn() {
    final now = _now();
    CoreadPost post(
      String id,
      String author,
      String articleId,
      int para,
      String quote,
      String thought,
      int hoursAgo,
      int likes,
    ) => CoreadPost(
      id: id,
      author: author,
      articleId: articleId,
      paraIndex: para,
      quote: quote,
      thought: thought,
      createdAt: now - hoursAgo * _hour,
      likes: likes,
    );
    return [
      post(
        'm1',
        'Lin',
        'daily-3-a',
        1,
        'One useful way to understand it is to treat it as a problem with '
            'feelings, not with time.',
        '原来拖延不是懒，是在躲情绪。今天先做五分钟，就当给自己一个台阶。',
        2,
        128,
      ),
      post(
        'm2',
        'Kai',
        'culture-3-a',
        2,
        'Every exhibition makes an argument, even if it does so quietly.',
        '下次逛博物馆，想想策展人在讲什么故事，还有那些没摆出来的东西。',
        20,
        86,
      ),
      post(
        'm3',
        'Mo',
        'tech-3-a',
        1,
        'the clearest clues about your taste are what you do, not what you '
            'say.',
        '推荐算法看的是你做了什么，而不是你说了什么。有点扎心。',
        54,
        203,
      ),
      post(
        'm4',
        'Yuki',
        'tech-2-a',
        2,
        'Heat is one of the biggest enemies.',
        '难怪夏天放车里的手机老得快，边充电边打游戏也要收敛点。',
        30,
        64,
      ),
      post(
        'm5',
        'Ana',
        'culture-1-a',
        0,
        'But every country has its own way to enjoy it.',
        '初级文章也很有味道，想去摩洛哥喝一次薄荷茶。',
        96,
        41,
      ),
    ];
  }

  /// Built-in comments: (post, author, text, minutes ago, likes, reply to).
  static const _seedComments = [
    ('m1', 'Kai', '五分钟法则真的有用，先开个头就停不下来了', 95, 32, null),
    ('m1', 'Mo', '“躲情绪”这个说法好准', 80, 21, null),
    ('m1', 'Lin', '对，开头最难，后面就顺了', 70, 6, 'Kai'),
    ('m1', 'Ana', 'feelings, not time —— 抄在便利贴上了', 40, 9, null),
    ('m1', 'Yuki', '今天的任务清单先拆成五分钟的小块', 15, 2, null),
    ('m2', 'Lin', '博物馆里的留白也是一种表达', 900, 14, null),
    ('m2', 'Ana', '下次去看展先读导览词，看策展人想说什么', 700, 5, null),
    ('m2', 'Kai', '“quietly” 用得真好', 600, 3, 'Lin'),
    ('m3', 'Yuki', '难怪我说不喜欢的视频还是一直被推荐 😂', 3000, 48, null),
    (
      'm3',
      'Kai',
      'what you do, not what you say —— 推荐系统比我更了解我',
      2800,
      26,
      null,
    ),
    ('m3', 'Mo', '确实，行动比口头偏好诚实多了', 2700, 11, 'Yuki'),
    ('m3', 'Lin', '这句可以拿来造句练习', 2000, 4, null),
    ('m4', 'Mo', '车里放手机真的伤电池，学到了', 1700, 7, null),
    ('m4', 'Ana', '充电到 80% 就拔是不是也有用？', 1500, 5, null),
    ('m4', 'Yuki', '文章里说热比充电次数更伤，夏天要注意', 1400, 3, 'Ana'),
    ('m5', 'Kai', '摩洛哥薄荷茶 +1，加很多糖那种', 5500, 6, null),
    ('m5', 'Lin', '初级文章读起来很放松', 5000, 2, null),
  ];

  List<CoreadComment> _builtInComments() {
    final now = _now();
    return [
      for (final (i, (post, author, text, minutes, likes, reply))
          in _seedComments.indexed)
        CoreadComment(
          id: 'c$i',
          postId: post,
          author: author,
          text: text,
          createdAt: now - minutes * _minute,
          likes: likes,
          replyTo: reply,
        ),
    ];
  }

  List<CoreadComment> _ownComments() {
    final raw = _prefs.getString(_commentsKey);
    if (raw == null) return const [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          CoreadComment.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Comments on [postId]: the user's own first (newest first), then the
  /// rest by likes.
  List<CoreadComment> comments(String postId) {
    final own = [
      for (final c in _ownComments())
        if (c.postId == postId) c,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final others = [
      for (final c in _builtInComments())
        if (c.postId == postId) c,
    ]..sort((a, b) => b.likes.compareTo(a.likes));
    return [...own, ...others];
  }

  /// Post id -> number of comments.
  Map<String, int> commentCounts() {
    final counts = <String, int>{};
    for (final c in [..._builtInComments(), ..._ownComments()]) {
      counts[c.postId] = (counts[c.postId] ?? 0) + 1;
    }
    return counts;
  }

  /// Posts the user commented on.
  Set<String> commentedPosts() => {for (final c in _ownComments()) c.postId};

  Future<CoreadComment> comment({
    required String postId,
    required String author,
    required String text,
    String? replyTo,
  }) async {
    final now = _now();
    final c = CoreadComment(
      id: 'uc$now',
      postId: postId,
      author: author,
      text: text,
      createdAt: now,
      replyTo: replyTo,
    );
    await _prefs.setString(
      _commentsKey,
      jsonEncode([c.toJson(), for (final o in _ownComments()) o.toJson()]),
    );
    return c;
  }

  Set<String> likedComments() => {...?_prefs.getStringList(_commentLikedKey)};

  Future<void> setCommentLiked(String commentId, bool like) {
    final ids = likedComments();
    like ? ids.add(commentId) : ids.remove(commentId);
    return _prefs.setStringList(_commentLikedKey, ids.toList());
  }

  List<CoreadPost> _own() {
    final raw = _prefs.getString(_postsKey);
    if (raw == null) return const [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          CoreadPost.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Every post, newest first.
  List<CoreadPost> posts() =>
      [..._own(), ..._builtIn()]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Set<String> liked() => {...?_prefs.getStringList(_likedKey)};

  Future<void> setLiked(String postId, bool like) {
    final ids = liked();
    like ? ids.add(postId) : ids.remove(postId);
    return _prefs.setStringList(_likedKey, ids.toList());
  }

  Future<CoreadPost> share({
    required String author,
    required String articleId,
    required int paraIndex,
    required String quote,
    required String thought,
  }) async {
    final now = _now();
    final post = CoreadPost(
      id: 'u$now',
      author: author,
      articleId: articleId,
      paraIndex: paraIndex,
      quote: quote,
      thought: thought,
      createdAt: now,
    );
    await _prefs.setString(
      _postsKey,
      jsonEncode([post.toJson(), for (final p in _own()) p.toJson()]),
    );
    return post;
  }
}
