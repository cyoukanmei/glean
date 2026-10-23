import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'analytics.dart';

/// Impression rule for list cards: at least [minFraction] of the card on
/// screen for [minDwell], counted once per session per list (surface).
class ImpressionTracker {
  ImpressionTracker(this.surface);

  final String surface;

  static const minFraction = 0.5;
  static const minDwell = Duration(milliseconds: 500);

  final _timers = <String, Timer>{};
  final _seen = <String>{};

  void _onVisibility(String articleId, int position, double fraction) {
    final key = '${Analytics.service?.sessionId}/$articleId';
    if (_seen.contains(key)) return;
    if (fraction >= minFraction) {
      _timers[articleId] ??= Timer(minDwell, () {
        _timers.remove(articleId);
        if (!_seen.add(key)) return;
        Analytics.track('article_impression', {
          'article_id': articleId,
          'surface': surface,
          'position': position,
        });
      });
    } else {
      _timers.remove(articleId)?.cancel();
    }
  }

  /// Wraps a card so its visibility feeds the rule above.
  Widget wrap({
    required String articleId,
    required int position,
    required Widget child,
  }) => VisibilityDetector(
    key: Key('impression-$surface-$articleId'),
    onVisibilityChanged: (info) =>
        _onVisibility(articleId, position, info.visibleFraction),
    child: child,
  );

  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }
}
