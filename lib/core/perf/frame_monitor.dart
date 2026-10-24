import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Build and raster time of one frame, in microseconds.
typedef FrameSample = ({int buildUs, int rasterUs});

/// Frame-time statistics against the display's real budget (8.3 ms at
/// 120 Hz, 16.7 ms at 60 Hz). A frame is janky when either its UI-thread
/// build or its raster-thread work overruns the budget, which is when the
/// engine misses a vsync.
class FrameStats {
  const FrameStats({
    required this.refreshRate,
    required this.count,
    required this.build,
    required this.raster,
    required this.jank,
  });

  factory FrameStats.of(List<FrameSample> samples, {required double hz}) {
    final budgetUs = 1e6 / hz;
    return FrameStats(
      refreshRate: hz,
      count: samples.length,
      build: Percentiles.of([for (final s in samples) s.buildUs]),
      raster: Percentiles.of([for (final s in samples) s.rasterUs]),
      jank: samples
          .where((s) => s.buildUs > budgetUs || s.rasterUs > budgetUs)
          .length,
    );
  }

  final double refreshRate;
  final int count;
  final Percentiles build;
  final Percentiles raster;
  final int jank;

  double get budgetMs => 1000 / refreshRate;
  double get jankPercent => count == 0 ? 0 : jank * 100 / count;

  Map<String, Object> toJson() => {
    'refresh_rate_hz': refreshRate.round(),
    'budget_ms': _ms(budgetMs * 1000),
    'frame_count': count,
    'build_ms': build.toJson(),
    'raster_ms': raster.toJson(),
    'jank_frames': jank,
    'jank_percent': double.parse(jankPercent.toStringAsFixed(2)),
  };
}

/// Average, p50 / p90 / p99 and worst of a list of microsecond values,
/// reported in milliseconds.
class Percentiles {
  const Percentiles(this.avg, this.p50, this.p90, this.p99, this.worst);

  factory Percentiles.of(List<int> us) {
    if (us.isEmpty) return const Percentiles(0, 0, 0, 0, 0);
    final s = [...us]..sort();
    double at(double q) => s[min(s.length - 1, (q * s.length).floor())] / 1000;
    return Percentiles(
      s.reduce((a, b) => a + b) / s.length / 1000,
      at(0.5),
      at(0.9),
      at(0.99),
      s.last / 1000,
    );
  }

  final double avg;
  final double p50;
  final double p90;
  final double p99;
  final double worst;

  Map<String, double> toJson() => {
    'avg': _ms(avg * 1000),
    'p50': _ms(p50 * 1000),
    'p90': _ms(p90 * 1000),
    'p99': _ms(p99 * 1000),
    'worst': _ms(worst * 1000),
  };
}

double _ms(num us) => double.parse((us / 1000).toStringAsFixed(2));

/// Records the timing of every rendered frame (the engine reports them in
/// batches, so this costs nothing per frame) into a ring buffer, for the
/// 性能监测 page and the profile-mode perf test.
class FrameMonitor {
  FrameMonitor._();

  static final instance = FrameMonitor._();

  /// About 30 s at 120 Hz.
  static const capacity = 3600;

  final _samples = <FrameSample>[];
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _samples.add((
        buildUs: t.buildDuration.inMicroseconds,
        rasterUs: t.rasterDuration.inMicroseconds,
      ));
    }
    final over = _samples.length - capacity;
    if (over > 0) _samples.removeRange(0, over);
  }

  List<FrameSample> get samples => List.unmodifiable(_samples);

  void reset() => _samples.clear();

  /// Current display refresh rate (adaptive panels report the active mode).
  static double get refreshRate {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final hz = views.isEmpty ? 60.0 : views.first.display.refreshRate;
    return hz > 0 ? hz : 60;
  }

  FrameStats stats() => FrameStats.of(_samples, hz: refreshRate);
}
