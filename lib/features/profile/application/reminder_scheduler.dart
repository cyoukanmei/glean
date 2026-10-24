/// The reminder's scheduler: local notifications on mobile, none on the web
/// (no background alarms in a browser tab).
library;

export 'reminder_scheduler_io.dart'
    if (dart.library.js_interop) 'reminder_scheduler_web.dart';
