import 'dart:async';

import 'package:visibility_detector/visibility_detector.dart';

/// Runs before every test file.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Report visibility synchronously, so impression tracking leaves no timer
  // pending when a widget test ends.
  VisibilityDetectorController.instance.updateInterval = Duration.zero;
  await testMain();
}
