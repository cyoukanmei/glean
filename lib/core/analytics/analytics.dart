import 'package:flutter/foundation.dart';

import 'analytics_service.dart';

/// Single entry point for tracking events from anywhere in the app.
///
/// `main` attaches the [AnalyticsService] (local queue + batched upload);
/// without one (widget tests) events only go to the debug console.
abstract final class Analytics {
  static AnalyticsService? _service;

  static AnalyticsService? get service => _service;

  static void attach(AnalyticsService? service) => _service = service;

  static void track(String name, [Map<String, Object?> params = const {}]) {
    if (kDebugMode) debugPrint('[analytics] $name $params');
    _service?.track(name, params);
  }
}
