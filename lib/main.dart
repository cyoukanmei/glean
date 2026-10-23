import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'app/providers.dart';
import 'core/db/app_database.dart';
import 'core/db/seed_importer.dart';
import 'core/navigation/swipe_back_route.dart';
import 'features/articles/ui/article_list_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final (db, prefs) = await (
    AppDatabase.open(),
    SharedPreferences.getInstance(),
  ).wait;

  // Not awaited: the UI starts right away and reads wait on this, so the
  // first launch shows the list skeleton while the seed is imported.
  final seedReady = _importSeed(db);

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        prefsProvider.overrideWithValue(prefs),
        seedReadyProvider.overrideWithValue(seedReady),
      ],
      child: const EnglishReaderApp(),
    ),
  );
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

class EnglishReaderApp extends StatelessWidget {
  const EnglishReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'English Reader',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      // Every page uses SwipeBackPageRoute, so the page underneath also gets
      // the parallax secondary animation while the top page slides.
      onGenerateRoute: (settings) => SwipeBackPageRoute<void>(
        settings: settings,
        builder: (_) => const ArticleListPage(),
      ),
    );
  }
}
