import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import '../../../core/perf/frame_monitor.dart';
import '../../../core/perf/startup_trace.dart';

/// 性能监测: live frame timings against the display's budget, a histogram
/// of recent frames, the image cache and this launch's startup milestones.
/// "输出到日志" prints the same numbers as JSON (`adb logcat -s flutter`).
class PerfPage extends StatefulWidget {
  const PerfPage({super.key});

  @override
  State<PerfPage> createState() => _PerfPageState();
}

class _PerfPageState extends State<PerfPage> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  void _log() {
    final cache = PaintingBinding.instance.imageCache;
    final report = {
      'frames': FrameMonitor.instance.stats().toJson(),
      'image_cache': {
        'bytes': cache.currentSizeBytes,
        'images': cache.currentSize,
        'live': cache.liveImageCount,
      },
      'startup_ms': {for (final (n, ms) in StartupTrace.marks) n: ms},
    };
    debugPrint('[perf] ${jsonEncode(report)}');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已输出到日志（[perf]）')));
  }

  @override
  Widget build(BuildContext context) {
    final monitor = FrameMonitor.instance;
    final stats = monitor.stats();
    final cache = PaintingBinding.instance.imageCache;
    String ms(double v) => v.toStringAsFixed(1);
    return Scaffold(
      appBar: AppBar(
        title: const Text('性能监测'),
        backgroundColor: GleanColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _Caption(
            '帧耗时 · ${stats.refreshRate.round()} Hz，'
            '预算 ${ms(stats.budgetMs)} ms',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _Big('${stats.count}', '帧'),
                _Big(
                  '${stats.jankPercent.toStringAsFixed(1)}%',
                  '超预算',
                  color: stats.jankPercent > 5
                      ? GleanColors.red
                      : GleanColors.tint,
                ),
                _Big(ms(stats.build.p90), 'UI p90 ms'),
                _Big(ms(stats.raster.p90), '光栅 p90 ms'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Histogram(samples: monitor.samples, budgetMs: stats.budgetMs),
          const SizedBox(height: 12),
          InsetGroup(
            children: [
              _Row(
                'UI 线程',
                '均 ${ms(stats.build.avg)} · p50 ${ms(stats.build.p50)} · '
                    'p99 ${ms(stats.build.p99)} · 最差 ${ms(stats.build.worst)}',
              ),
              _Row(
                '光栅线程',
                '均 ${ms(stats.raster.avg)} · p50 ${ms(stats.raster.p50)} · '
                    'p99 ${ms(stats.raster.p99)} · 最差 ${ms(stats.raster.worst)}',
              ),
              _Row('超预算帧', '${stats.jank} / ${stats.count}'),
            ],
          ),
          const _Caption('图片缓存'),
          InsetGroup(
            children: [
              _Row(
                '已解码',
                '${(cache.currentSizeBytes / 1048576).toStringAsFixed(1)} MB'
                    ' · ${cache.currentSize} 张',
              ),
              _Row('正在显示', '${cache.liveImageCount} 张'),
            ],
          ),
          const _Caption('本次冷启动（自 main 起，毫秒）'),
          InsetGroup(
            children: [
              for (final (name, at) in StartupTrace.marks) _Row(name, '$at ms'),
            ],
          ),
          const SizedBox(height: 20),
          InsetGroup(
            children: [
              ListTile(
                key: const Key('perf-reset'),
                title: const Text('重置帧统计'),
                trailing: const Icon(Icons.restart_alt_rounded),
                onTap: () => setState(monitor.reset),
              ),
              ListTile(
                key: const Key('perf-log'),
                title: const Text('输出到日志'),
                subtitle: const Text('adb logcat -s flutter | grep perf'),
                trailing: const Icon(Icons.terminal_rounded),
                onTap: _log,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The last ~240 frames as bars (build + raster stacked), with the budget
/// as a line; bars over it turn red.
class _Histogram extends StatelessWidget {
  const _Histogram({required this.samples, required this.budgetMs});

  final List<FrameSample> samples;
  final double budgetMs;

  @override
  Widget build(BuildContext context) {
    final recent = samples.length > 240
        ? samples.sublist(samples.length - 240)
        : samples;
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GleanColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: GleanColors.cardShadow,
      ),
      child: CustomPaint(
        size: Size.infinite,
        painter: _BarsPainter(
          recent,
          budgetMs: budgetMs,
          ok: GleanColors.tintBright,
          bad: GleanColors.red,
          line: GleanColors.label3,
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(
    this.samples, {
    required this.budgetMs,
    required this.ok,
    required this.bad,
    required this.line,
  });

  final List<FrameSample> samples;
  final double budgetMs;
  final Color ok;
  final Color bad;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    // Scale so the budget sits at 40 % of the height.
    final maxMs = budgetMs * 2.5;
    double y(double ms) => size.height * (1 - (ms / maxMs).clamp(0.0, 1.0));
    final w = size.width / 240;
    final paint = Paint();
    for (final (i, s) in samples.indexed) {
      final worst = (s.buildUs > s.rasterUs ? s.buildUs : s.rasterUs) / 1000;
      paint.color = worst > budgetMs ? bad : ok.withValues(alpha: 0.75);
      canvas.drawRect(
        Rect.fromLTRB(i * w, y(worst), i * w + w * 0.7, size.height),
        paint,
      );
    }
    canvas.drawLine(
      Offset(0, y(budgetMs)),
      Offset(size.width, y(budgetMs)),
      Paint()
        ..color = line
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BarsPainter old) => true;
}

class _Big extends StatelessWidget {
  const _Big(this.value, this.label, {this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color ?? GleanColors.label,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: GleanColors.label2),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.title, this.value);

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: GleanColors.label2),
            ),
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 22, 32, 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: GleanColors.label2),
      ),
    );
  }
}
