import 'package:clock/clock.dart';

/// Milliseconds since epoch. Injected into repositories so tests can control
/// time and ordering of writes.
typedef Clock = int Function();

/// Wall time via package:clock: real time in the app, and flutter_test's
/// fake time inside widget tests, so timers and timestamps agree there.
int systemClock() => clock.now().millisecondsSinceEpoch;
