import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/db/app_database.dart';
import '../../../core/platform/local_notifications.dart';
import '../../articles/data/article_remote.dart';
import '../../articles/data/article_repository.dart';
import '../../auth/application/auth.dart';
import '../../auth/data/auth_repository.dart';
import '../data/mock_sync_server.dart';
import '../sync_service.dart';
import 'background_job.dart';

const supportsBackgroundSync = true;

const _task = 'glean.background_sync';
const _lastRunKey = 'background_sync.last_run';
const _lastNewKey = 'background_sync.last_new';
const _storePayload = 'store';
const _notificationId = 2;

/// Called by WorkManager in a fresh background engine (or in the running
/// app's engine for a one-off run).
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await _runInBackground();
      return true;
    } catch (e, s) {
      debugPrint('[background] failed: $e\n$s');
      return false;
    }
  });
}

/// From main: an hourly run whenever the phone is online, and tapping a
/// new-article notification opens 书城 ([openStore]).
Future<void> startBackgroundSync({required void Function() openStore}) async {
  void open(String? payload) {
    if (payload != _storePayload) return;
    Analytics.track('notification_open', {'kind': 'new_articles'});
    openStore();
  }

  LocalNotifications.onTap = open;
  open(await LocalNotifications.launchPayload());
  await Workmanager().initialize(backgroundDispatcher);
  await Workmanager().registerPeriodicTask(
    _task,
    _task,
    frequency: const Duration(hours: 1),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

/// 同步 page: the same work once, through WorkManager, as soon as there is
/// a network connection (offline it waits, like the hourly run).
Future<void> runBackgroundSyncNow() => Workmanager().registerOneOffTask(
  '$_task.now',
  _task,
  constraints: Constraints(networkType: NetworkType.connected),
  existingWorkPolicy: ExistingWorkPolicy.replace,
);

Future<BackgroundStatus?> backgroundStatus() async {
  final prefs = await SharedPreferences.getInstance();
  // Written by the background engine's own prefs instance.
  await prefs.reload();
  final at = prefs.getInt(_lastRunKey);
  if (at == null) return null;
  return BackgroundStatus(at: at, newArticles: prefs.getInt(_lastNewKey) ?? 0);
}

Future<void> _runInBackground() async {
  // Same files as the app; when the app is running, sqflite hands back the
  // connection it already has open.
  final (db, prefs) = await (
    AppDatabase.open(),
    SharedPreferences.getInstance(),
  ).wait;
  final token = prefs.getString(AuthNotifier.tokenKey);
  final user = token == null
      ? null
      : await AuthRepository(db).userForToken(token);
  final deviceId = prefs.getString(AnalyticsService.deviceIdKey);

  Future<SyncResult> Function()? sync;
  if (user != null && deviceId != null) {
    final serverDb = await MockSyncServer.open(
      databaseFactory,
      p.join(await getDatabasesPath(), 'mock_server.db'),
    );
    sync = SyncService(
      db: db,
      server: MockSyncServer(serverDb, isOnline: () => true),
      deviceId: deviceId,
      userId: () => user.id,
      // WorkManager only starts the task with a network connection.
      isOnline: () => true,
      onRemoteChanges: () {},
    ).sync;
  }

  final run = await BackgroundJob(
    articles: ArticleRepository(db),
    remote: MockArticleRemote(
      loadPool: () => rootBundle.loadString('assets/seed/remote_pool.json'),
    ),
    notify: _notifyNewArticles,
    sync: sync,
  ).run();
  await prefs.setInt(_lastRunKey, DateTime.now().millisecondsSinceEpoch);
  await prefs.setInt(_lastNewKey, run.newTitles.length);
  debugPrint(
    '[background] new=${run.newTitles.length} '
    'sync=${run.sync?.skipped ?? run.sync?.error ?? 'ok'}',
  );
}

/// Only if notifications are already allowed: a background task never asks.
Future<void> _notifyNewArticles(List<String> titles) async {
  await LocalNotifications.ensureInitialized();
  if (await LocalNotifications.android?.areNotificationsEnabled() == false) {
    return;
  }
  await LocalNotifications.plugin.show(
    id: _notificationId,
    title: '书城上新 ${titles.length} 篇',
    body: titles.join(' · '),
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'new_articles',
        '新文章',
        channelDescription: '后台同步发现书城有新文章时提醒',
      ),
    ),
    payload: _storePayload,
  );
}
