import '../../articles/data/article_remote.dart';
import '../../articles/data/article_repository.dart';
import '../sync_service.dart';

/// When the last background run finished and how many articles it brought
/// in (shown on the 同步 page).
class BackgroundStatus {
  const BackgroundStatus({required this.at, required this.newArticles});

  final int at;
  final int newArticles;
}

/// What one background run did.
class BackgroundRun {
  const BackgroundRun({required this.newTitles, this.sync});

  /// Titles of the articles it brought in.
  final List<String> newTitles;
  final SyncResult? sync;
}

/// One background pass while the app is closed: bring newly published
/// articles into the local database (the same request as 书城's pull to
/// refresh), announce them, and sync reading progress and words.
class BackgroundJob {
  BackgroundJob({
    required this.articles,
    required this.remote,
    required this.notify,
    this.sync,
  });

  final ArticleRepository articles;
  final MockArticleRemote remote;

  /// Shows the "new articles" notification.
  final Future<void> Function(List<String> titles) notify;

  /// Null when nobody is signed in (guests do not sync).
  final Future<SyncResult> Function()? sync;

  Future<BackgroundRun> run() async {
    final fresh = await remote.fetchLatest(articles.knownIds);
    await articles.upsertAll(fresh);
    final titles = [for (final a in fresh) a['title']! as String];
    if (titles.isNotEmpty) await notify(titles);
    return BackgroundRun(newTitles: titles, sync: await sync?.call());
  }
}
