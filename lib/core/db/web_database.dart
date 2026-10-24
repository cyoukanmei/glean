/// On the web, sqflite runs on SQLite compiled to WebAssembly
/// (web/sqlite3.wasm) with its files in IndexedDB; on mobile this is a
/// no-op and sqflite uses the platform's SQLite.
library;

export 'web_database_io.dart'
    if (dart.library.js_interop) 'web_database_web.dart';
