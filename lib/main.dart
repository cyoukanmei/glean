import 'dart:convert';
import 'dart:math';

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
import 'core/db/web_database.dart';
import 'core/navigation/swipe_back_route.dart';
import 'core/perf/frame_monitor.dart';
import 'core/perf/startup_trace.dart';
import 'app/app_root.dart';
import 'app/appearance.dart';
import 'core/design/glean_colors.dart';
import 'core/design/glean_theme.dart';
import 'features/auth/application/auth.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/profile/application/reminder.dart';
import 'features/sync/data/mock_sync_server.dart';
import 'features/sync/sync_service.dart';

Future<void> main() async {
  StartupTrace.begin();
  WidgetsFlutterBinding.ensureInitialized();
  useWebDatabaseIfNeeded();
  FrameMonitor.instance.start();
  StartupTrace.mark('binding');

  // Independent I/O runs side by side instead of one after another.
  final covers = CoverCatalog.load(rootBundle);
  final package = PackageInfo.fromPlatform();
  final serverDb = getDatabasesPath().then(
    (dir) =>
        MockSyncServer.open(databaseFactory, p.join(dir, 'mock_server.db')),
  );
  final (db, prefs) = await (
    AppDatabase.open(),
    SharedPreferences.getInstance(),
  ).wait;
  StartupTrace.mark('database');

  // Not awaited: the UI starts right away and reads wait on this, so the
  // first launch shows the list skeleton while the seed is imported.
  final seedReady = _importSeed(db);
  final (user, packageInfo, _, server) = await (
    _restoreSession(db, prefs),
    package,
    covers,
    serverDb,
  ).wait;
  StartupTrace.mark('session');

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
    appVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
    platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
    userId: () => container.read(currentUserIdProvider),
    isOnline: online,
  );
  Analytics.attach(analytics);

  final sync = SyncService(
    db: db,
    server: MockSyncServer(server, isOnline: online),
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
  StartupTrace.mark('run_app');
  // Cold start (Dart side) = start of main to the first frame on screen.
  await WidgetsBinding.instance.endOfFrame;
  StartupTrace.mark('first_frame');
  await analytics.start(coldStartMs: StartupTrace.elapsedMs);
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
    aiJson: await rootBundle.loadString('assets/seed/ai.json'),
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
    // A reminder cleared by a force-stop or an update comes back.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(reminderProvider.notifier).restore(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from settings (e.g. after allowing exact alarms) or a long pause.
    if (state == AppLifecycleState.resumed) {
      ref.read(reminderProvider.notifier).restore();
    }
  }

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
        child: kIsWeb ? _PhoneFrame(child: child!) : child!,
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

/// The H5 build in a wide browser window: the app in a phone-sized frame in
/// the middle of the page, with MediaQuery reporting the frame's size, so
/// every layout that reads the screen size behaves as on a phone. On a
/// phone-width window it fills the window.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});

  final Widget child;

  static const width = 430.0;
  static const maxHeight = 932.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width <= width + 90) return child;
    final size = Size(width, min(media.size.height - 48, maxHeight));
    return ColoredBox(
      color: const Color(0xFFDCD7CE),
      child: Center(
        child: Container(
          width: size.width,
          height: size.height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 50,
                offset: Offset(0, 24),
                spreadRadius: -20,
              ),
            ],
          ),
          child: MediaQuery(
            data: media.copyWith(size: size, padding: EdgeInsets.zero),
            child: child,
          ),
        ),
      ),
    );
  }
}
