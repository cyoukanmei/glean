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
    this.comments = 0,
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
    comments: j['comments'] as int? ?? 0,
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
  final int comments;

  Map<String, Object> toJson() => {
    'id': id,
    'author': author,
    'articleId': articleId,
    'paraIndex': paraIndex,
    'quote': quote,
    'thought': thought,
    'createdAt': createdAt,
    'likes': likes,
    'comments': comments,
  };
}

/// Local stand-in for a community backend: a few built-in posts plus the
/// user's own shares and likes, kept in shared preferences.
class CoreadStore {
  CoreadStore(this._prefs, {required this._now});

  final SharedPreferences _prefs;
  final int Function() _now;

  static const _postsKey = 'coread.posts';
  static const _likedKey = 'coread.liked';
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
      int comments,
    ) => CoreadPost(
      id: id,
      author: author,
      articleId: articleId,
      paraIndex: para,
      quote: quote,
      thought: thought,
      createdAt: now - hoursAgo * _hour,
      likes: likes,
      comments: comments,
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
        16,
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
        9,
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
        31,
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
        5,
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
        3,
      ),
    ];
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
