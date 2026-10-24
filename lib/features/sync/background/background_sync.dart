/// Background sync: WorkManager on Android, nothing on the web (a closed
/// browser tab cannot run code).
library;

export 'background_job.dart' show BackgroundStatus;
export 'background_sync_io.dart'
    if (dart.library.js_interop) 'background_sync_web.dart';
