import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// SQLite in WebAssembly, persisted in IndexedDB. Runs on the main thread
/// (no shared worker to build or serve); the app's data is small.
void useWebDatabaseIfNeeded() {
  databaseFactory = databaseFactoryFfiWebNoWebWorker;
}
