import 'package:flutter/foundation.dart';

/// Milestones of a cold start, measured from the first line of `main`
/// (the Dart side; the engine's own start is added by the system's
/// `am start -W` figure, see README).
abstract final class StartupTrace {
  static final _watch = Stopwatch()..start();
  static final _marks = <(String, int)>[];

  /// Restarts the clock; call first thing in `main`.
  static void begin() {
    _watch.reset();
    _marks.clear();
  }

  static void mark(String name) {
    _marks.add((name, _watch.elapsedMilliseconds));
    debugPrint('[startup] $name ${_watch.elapsedMilliseconds}ms');
  }

  /// (milestone, ms since `main`) in order.
  static List<(String, int)> get marks => List.unmodifiable(_marks);

  static int get elapsedMs => _watch.elapsedMilliseconds;
}
