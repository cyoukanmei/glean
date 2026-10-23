import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'schema.dart';

abstract final class AppDatabase {
  static const fileName = 'glean.db';

  /// Opens (creating or migrating) the app database.
  ///
  /// [factory] and [path] are injectable so tests can use sqflite_common_ffi
  /// with a temp file; [version] lets migration tests open an older schema.
  static Future<Database> open({
    DatabaseFactory? factory,
    String? path,
    int version = kSchemaVersion,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    return f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: _configure,
        onCreate: (db, version) => _migrate(db, 0, version),
        onUpgrade: _migrate,
      ),
    );
  }

  static Future<void> _configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    // WAL + NORMAL: committed transactions survive an app crash or kill; only
    // power loss / OS crash may roll back the most recent commits.
    // journal_mode returns a row, so Android requires rawQuery here.
    await db.rawQuery('PRAGMA journal_mode = WAL');
    await db.execute('PRAGMA synchronous = NORMAL');
  }

  /// sqflite runs onCreate/onUpgrade inside one transaction, so a failed
  /// migration leaves the previous version intact.
  static Future<void> _migrate(Database db, int from, int to) async {
    final batch = db.batch();
    if (from < 1) {
      for (final sql in schemaV1) {
        batch.execute(sql);
      }
    }
    for (var v = max(from, 1) + 1; v <= to; v++) {
      for (final sql in migrations[v]!) {
        batch.execute(sql);
      }
    }
    await batch.commit(noResult: true);
  }
}
