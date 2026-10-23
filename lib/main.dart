import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'core/db/app_database.dart';
import 'core/db/seed_importer.dart';
import 'core/navigation/swipe_back_route.dart';
import 'features/articles/data/article_repository.dart';
import 'features/articles/ui/article_list_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();

  final sw = Stopwatch()..start();
  final seed = SeedBundle.fromJson(
    articlesJson: await rootBundle.loadString('assets/seed/articles.json'),
    dictJson: await rootBundle.loadString('assets/seed/dict.json'),
  );
  final imported = await SeedImporter.importIfNeeded(db, seed);
  debugPrint('[seed] imported=$imported in ${sw.elapsedMilliseconds}ms');

  runApp(EnglishReaderApp(db: db));
}

class EnglishReaderApp extends StatelessWidget {
  const EnglishReaderApp({super.key, required this.db});

  final Database db;

  @override
  Widget build(BuildContext context) {
    final articles = ArticleRepository(db);
    return MaterialApp(
      title: 'English Reader',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      // Every page uses SwipeBackPageRoute, so the page underneath also gets
      // the parallax secondary animation while the top page slides.
      onGenerateRoute: (settings) => SwipeBackPageRoute<void>(
        settings: settings,
        builder: (_) => ArticleListPage(repository: articles),
      ),
    );
  }
}
