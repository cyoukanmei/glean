import 'dart:io';

import 'package:glean/core/db/app_database.dart';
import 'package:glean/core/db/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens a real SQLite file in a temp dir (WAL needs a file, not :memory:).
///
/// Tear-downs run last-registered-first: the database is closed before its
/// directory is removed.
Future<Database> openTestDb({
  int version = kSchemaVersion,
  String? path,
}) async {
  sqfliteFfiInit();
  final dbPath = path ?? await newTestDbPath();
  final db = await AppDatabase.open(
    factory: databaseFactoryFfi,
    path: dbPath,
    version: version,
  );
  addTearDown(db.close);
  return db;
}

Future<String> newTestDbPath() async {
  final dir = await Directory.systemTemp.createTemp('glean_test_');
  addTearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Windows may hold the WAL file briefly; a leftover temp dir is harmless.
    }
  });
  return p.join(dir.path, 'test.db');
}

/// Minimal article row so foreign keys on reading_progress are satisfied.
Future<void> insertArticle(Database db, String id) {
  return db.insert('articles', {
    'id': id,
    'title': 'Title $id',
    'category': 'tech',
    'level': 1,
    'body': '["Hello world."]',
    'word_count': 2,
    'published_at': 0,
  });
}

/// Monotonic fake clock: every call returns a later millisecond.
class FakeClock {
  FakeClock([this.now = 1000]);

  int now;

  int call() => now++;
}
