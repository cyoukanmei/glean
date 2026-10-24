/// Files kept on the device (photos), which the web build does not have:
/// the mobile implementation uses dart:io, the web one says it cannot.
library;

export 'local_files_io.dart'
    if (dart.library.js_interop) 'local_files_web.dart';
