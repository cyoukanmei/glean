import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'core/db/app_database.dart';
import 'core/db/seed_importer.dart';

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
    return MaterialApp(
      title: 'English Reader',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: _DbCheckPage(db: db),
    );
  }
}

/// Temporary page to verify the database and seed on a real device.
/// Replaced by the article list in the next step.
class _DbCheckPage extends StatelessWidget {
  const _DbCheckPage({required this.db});

  final Database db;

  Future<(Map<String, int>, List<Map<String, Object?>>)> _load() async {
    final counts = <String, int>{};
    for (final table in ['articles', 'dict', 'word_forms', 'app_meta']) {
      final r = await db.rawQuery('SELECT COUNT(*) AS n FROM $table');
      counts[table] = r.single['n']! as int;
    }
    final articles = await db.query(
      'articles',
      columns: ['title', 'category', 'level', 'word_count'],
      orderBy: 'published_at DESC, id DESC',
    );
    return (counts, articles);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DB check')),
      body: FutureBuilder(
        future: _load(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (counts, articles) = snap.data!;
          return ListView(
            children: [
              ListTile(title: Text(counts.toString())),
              for (final a in articles)
                ListTile(
                  dense: true,
                  title: Text(a['title']! as String),
                  subtitle: Text(
                    '${a['category']} · L${a['level']} · ${a['word_count']} words',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
