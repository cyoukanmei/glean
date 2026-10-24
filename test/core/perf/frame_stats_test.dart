import 'package:flutter_test/flutter_test.dart';
import 'package:glean/core/perf/frame_monitor.dart';

void main() {
  test('jank counts frames over the 120 Hz budget on either thread', () {
    final samples = [
      for (var i = 0; i < 97; i++) (buildUs: 4000, rasterUs: 5000),
      (buildUs: 9000, rasterUs: 3000), // UI over 8.3 ms
      (buildUs: 3000, rasterUs: 12000), // raster over
      (buildUs: 8000, rasterUs: 8000), // just under
    ];
    final s = FrameStats.of(samples, hz: 120);
    expect(s.count, 100);
    expect(s.budgetMs, closeTo(8.33, 0.01));
    expect(s.jank, 2);
    expect(s.jankPercent, 2);
    expect(s.build.p50, 4);
    expect(s.raster.worst, 12);
    expect(s.toJson()['jank_percent'], 2.0);
  });

  test('the same frames at 60 Hz have no jank', () {
    final s = FrameStats.of([(buildUs: 9000, rasterUs: 12000)], hz: 60);
    expect(s.jank, 0);
  });
}
