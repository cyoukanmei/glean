import 'package:flutter_test/flutter_test.dart';
import 'package:glean/features/coread/data/coread_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<CoreadStore> _store({int now = 1000000000000}) async {
  SharedPreferences.setMockInitialValues({});
  return CoreadStore(await SharedPreferences.getInstance(), now: () => now);
}

void main() {
  test('built-in posts come newest first', () async {
    final posts = (await _store()).posts();
    expect(posts, isNotEmpty);
    for (var i = 1; i < posts.length; i++) {
      expect(posts[i - 1].createdAt, greaterThanOrEqualTo(posts[i].createdAt));
    }
  });

  test('a shared post goes on top and survives a restart', () async {
    final store = await _store();
    final post = await store.share(
      author: 'demo',
      articleId: 'tech-2-a',
      paraIndex: 2,
      quote: 'Heat is one of the biggest enemies.',
      thought: '记住了',
    );
    expect(store.posts().first.id, post.id);

    final again = CoreadStore(
      await SharedPreferences.getInstance(),
      now: () => 0,
    );
    expect(again.posts().map((p) => p.id), contains(post.id));
  });

  test('likes persist', () async {
    final store = await _store();
    await store.setLiked('m1', true);
    await store.setLiked('m2', true);
    await store.setLiked('m1', false);
    expect(store.liked(), {'m2'});
  });

  test(
    'own comments come first, newest first, and survive a restart',
    () async {
      var now = 1000000000000;
      SharedPreferences.setMockInitialValues({});
      final store = CoreadStore(
        await SharedPreferences.getInstance(),
        now: () => now++,
      );
      final before = store.commentCounts()['m1']!;
      final builtIn = store.comments('m1');
      for (var i = 1; i < builtIn.length; i++) {
        expect(builtIn[i - 1].likes, greaterThanOrEqualTo(builtIn[i].likes));
      }

      await store.comment(postId: 'm1', author: 'demo', text: '第一条');
      final reply = await store.comment(
        postId: 'm1',
        author: 'demo',
        text: '同意',
        replyTo: 'Kai',
      );
      final again = CoreadStore(
        await SharedPreferences.getInstance(),
        now: () => now,
      );
      final comments = again.comments('m1');
      expect(comments.take(2).map((c) => c.text), ['同意', '第一条']);
      expect(comments.first.replyTo, 'Kai');
      expect(comments.first.own, isTrue);
      expect(again.commentCounts()['m1'], before + 2);
      expect(again.commentedPosts(), {'m1'});

      await again.setCommentLiked(reply.id, true);
      expect(again.likedComments(), {reply.id});
    },
  );
}
