import 'package:flutter/foundation.dart';

/// Single entry point for tracking events.
///
/// Call sites are wired from day one so every feature reports as it is built.
/// For now events only go to the debug console; the SQLite-backed queue with
/// batched upload replaces this body later without touching call sites.
abstract final class Analytics {
  static void track(String name, [Map<String, Object?> params = const {}]) {
    if (kDebugMode) debugPrint('[analytics] $name $params');
  }
}
