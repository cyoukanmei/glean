import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'app/providers.dart';
import 'core/analytics/analytics.dart';
import 'core/analytics/analytics_service.dart';
import 'core/analytics/collector.dart';
import 'core/analytics/event_queue.dart';
import 'core/widgets/cover_catalog.dart';
import 'core/db/app_database.dart';
import 'core/db/seed_importer.dart';
import 'core/navigation/swipe_back_route.dart';
import 'app/app_root.dart';
import 'app/appearance.dart';
import 'core/design/glean_colors.dart';
import 'core/design/glean_theme.dart';
import 'features/auth/application/auth.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/sync/data/mock_sync_server.dart';
import 'features/sync/sync_service.dart';

Future<void> main() async {
  final coldStart = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  final (db, prefs) = await (
    AppDatabase.open(),
    SharedPreferences.getInstance(),
  ).wait;

  // Not awaited: the UI starts right away and reads wait on this, so the
  // first launch shows the list skeleton while the seed is imported.
  final seedReady = _importSeed(db);
  await CoverCatalog.load(rootBundle);
  final (user, package) = await (
    _restoreSession(db, prefs),
    PackageInfo.fromPlatform(),
  ).wait;

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      prefsProvider.overrideWithValue(prefs),
      seedReadyProvider.overrideWithValue(seedReady),
      initialUserProvider.overrideWithValue(user),
    ],
  );
  bool online() => container.read(onlineProvider).value ?? true;
  final analytics = AnalyticsService(
    queue: EventQueue(db),
    collector: MockCollector(db, isOnline: online),
    deviceId: _deviceId(prefs),
    appVersion: '${package.version}+${package.buildNumber}',
    platform: defaultTargetPlatform.name,
    userId: () => container.read(currentUserIdProvider),
    isOnline: online,
  );
  Analytics.attach(analytics);

  final serverDb = await MockSyncServer.open(
    databaseFactory,
    p.join(await getDatabasesPath(), 'mock_server.db'),
  );
  final sync = SyncService(
    db: db,
    server: MockSyncServer(serverDb, isOnline: online),
    deviceId: _deviceId(prefs),
    userId: () => container.read(currentUserIdProvider),
    isOnline: online,
    onRemoteChanges: () {
      container.read(progressRevisionProvider.notifier).bump();
      container.read(vocabRevisionProvider.notifier).bump();
    },
  );

  container
    ..listen(onlineProvider, (_, next) {
      final isOnline = next.value ?? true;
      analytics.onConnectivityChanged(isOnline);
      sync.onConnectivityChanged(isOnline);
    })
    // Local writes and sign-ins schedule a sync a few seconds later.
    ..listen(progressRevisionProvider, (_, _) => sync.scheduleSoon())
    ..listen(vocabRevisionProvider, (_, _) => sync.scheduleSoon())
    ..listen(authProvider, (_, _) => sync.scheduleSoon());

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: ProviderScope(
        overrides: [
          analyticsServiceProvider.overrideWithValue(analytics),
          syncServiceProvider.overrideWithValue(sync),
        ],
        child: const GleanApp(),
      ),
    ),
  );
  // Cold start = process start to the first frame on screen.
  await WidgetsBinding.instance.endOfFrame;
  await analytics.start(coldStartMs: coldStart.elapsedMilliseconds);
  sync.start();
}

/// Random id per install, kept in prefs; not tied to the hardware.
String _deviceId(SharedPreferences prefs) {
  const key = 'analytics.device_id';
  final saved = prefs.getString(key);
  if (saved != null) return saved;
  final id = const Uuid().v4();
  prefs.setString(key, id);
  return id;
}

Future<void> _importSeed(Database db) async {
  final sw = Stopwatch()..start();
  // Every launch reads only the tiny manifest; the ~250 KB of seed JSON is
  // loaded and parsed only when a newer seed ships.
  final manifest =
      jsonDecode(await rootBundle.loadString('assets/seed/manifest.json'))
          as Map<String, dynamic>;
  final installed = await SeedImporter.installedVersion(db);
  if (installed != null && installed >= (manifest['seed_version'] as int)) {
    debugPrint(
      '[seed] up to date (v$installed) in ${sw.elapsedMilliseconds}ms',
    );
    return;
  }
  final seed = SeedBundle.fromJson(
    articlesJson: await rootBundle.loadString('assets/seed/articles.json'),
    dictJson: await rootBundle.loadString('assets/seed/dict.json'),
  );
  final imported = await SeedImporter.importIfNeeded(db, seed);
  debugPrint('[seed] imported=$imported in ${sw.elapsedMilliseconds}ms');
}

/// The account behind the saved token, if it is still valid. An unknown or
/// expired token is dropped, so the app opens on the login page.
Future<AuthUser?> _restoreSession(Database db, SharedPreferences prefs) async {
  final token = prefs.getString(AuthNotifier.tokenKey);
  if (token == null) return null;
  final user = await AuthRepository(db).userForToken(token);
  if (user == null) await prefs.remove(AuthNotifier.tokenKey);
  return user;
}

/// Picks light or dark from the 外观 setting (or the system), sets the
/// palette before anything below builds, and repaints the whole tree in
/// place when it flips.
class GleanApp extends ConsumerStatefulWidget {
  const GleanApp({super.key});

  @override
  ConsumerState<GleanApp> createState() => _GleanAppState();
}

class _GleanAppState extends ConsumerState<GleanApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(appearanceProvider);
    final platformDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final dark = switch (appearance) {
      Appearance.system => platformDark,
      Appearance.light => false,
      Appearance.dark => true,
    };
    final colorTheme = ref.watch(colorThemeProvider);
    if (dark != GleanColors.dark || colorTheme != GleanColors.theme) {
      GleanColors.dark = dark;
      GleanColors.theme = colorTheme;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) rebuildAllChildren(context);
      });
    }
    return MaterialApp(
      title: '拾读 Glean',
      theme: gleanTheme(),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: child!,
      ),
      scrollBehavior: const GleanScrollBehavior(),
      debugShowCheckedModeBanner: false,
      // Every page uses SwipeBackPageRoute, so the page underneath also gets
      // the parallax secondary animation while the top page slides.
      onGenerateRoute: (settings) => SwipeBackPageRoute<void>(
        settings: settings,
        builder: (_) => const AppRoot(),
      ),
    );
  }
}
