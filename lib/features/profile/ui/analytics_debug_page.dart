import 'package:clock/clock.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics_report.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/analytics/event_queue.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';

/// 埋点调试面板: queue state, upload history, pending events, failure
/// injection, and the analysis queries over what the mock server received.
class AnalyticsDebugPage extends ConsumerStatefulWidget {
  const AnalyticsDebugPage({super.key});

  @override
  ConsumerState<AnalyticsDebugPage> createState() => _AnalyticsDebugPageState();
}

class _Snapshot {
  const _Snapshot({
    required this.counts,
    required this.uploads,
    required this.pending,
    required this.reading,
    required this.funnel,
    required this.ctr,
  });

  final Map<int, int> counts;
  final List<UploadRecord> uploads;
  final List<QueuedEvent> pending;
  final List<(DateTime, double, int)> reading;
  final (int, int, int) funnel;
  final List<(String, int, int)> ctr;
}

class _AnalyticsDebugPageState extends ConsumerState<AnalyticsDebugPage> {
  late final AnalyticsService? _service = ref.read(analyticsServiceProvider);
  _Snapshot? _snap;
  bool _flushing = false;

  @override
  void initState() {
    super.initState();
    _service?.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _service?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final service = _service;
    if (service == null) return;
    final db = ref.read(databaseProvider);
    final report = AnalyticsReport(db);
    final now = clock.now();
    final since = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final queue = service.queue;
    final (counts, uploads, pending, reading, funnel, ctr) = await (
      queue.counts(),
      queue.uploads(limit: 10),
      queue.recent(status: EventStatus.pending, limit: 30),
      report.readingByDay(now),
      report.funnel(since),
      report.clickThrough(since),
    ).wait;
    if (!mounted) return;
    setState(
      () => _snap = _Snapshot(
        counts: counts,
        uploads: uploads,
        pending: pending,
        reading: reading,
        funnel: funnel,
        ctr: ctr,
      ),
    );
  }

  Future<void> _flush() async {
    final service = _service;
    if (service == null) return;
    setState(() => _flushing = true);
    final r = await service.flush();
    if (!mounted) return;
    setState(() => _flushing = false);
    final text = r.skipped != null
        ? '未上报：${r.skipped == 'offline' ? '当前离线' : r.skipped}'
        : r.failed > 0
        ? '上报失败 ${r.failed} 条，已按退避策略排队重试'
        : '已上报 ${r.sent} 条';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// A consistent copy of the database (`VACUUM INTO`) in the app's
  /// external files folder, which `adb pull` can read; the summary script
  /// runs on it (README section 7).
  Future<void> _export() async {
    final dir = await getExternalStorageDirectory();
    if (dir == null || !mounted) return;
    final path = p.join(
      dir.path,
      'glean-export-${clock.now().millisecondsSinceEpoch}.db',
    );
    await ref.read(databaseProvider).execute('VACUUM INTO ?', [path]);
    if (!mounted) return;
    final command = 'adb pull $path';
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('已导出'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '$command\n\n然后运行：\n'
            'python -I tool/analytics_report.py '
            '${p.basename(path)} --html report.html',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: command));
              Navigator.pop(context);
            },
            child: const Text('复制命令'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    final snap = _snap;
    return Scaffold(
      appBar: AppBar(
        title: const Text('埋点调试面板'),
        backgroundColor: GleanColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: service == null
          ? const Center(child: Text('埋点服务未启动'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                _Caption('会话'),
                InsetGroup(
                  children: [
                    _Kv('session_id', service.sessionId),
                    _Kv('device_id', service.deviceId),
                    _Kv('app_version', service.appVersion),
                    _Kv('platform', service.platform),
                  ],
                ),
                _Caption('队列'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _Count('待上报', snap?.counts[EventStatus.pending]),
                      _Count('发送中', snap?.counts[EventStatus.sending]),
                      _Count(
                        '已上报',
                        snap?.counts[EventStatus.sent],
                        color: GleanColors.tint,
                      ),
                      _Count(
                        '已放弃',
                        snap?.counts[EventStatus.dead],
                        color: GleanColors.red,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                InsetGroup(
                  children: [
                    ListTile(
                      key: const Key('debug-flush'),
                      title: const Text('立即上报'),
                      trailing: _flushing
                          ? const CupertinoActivityIndicator()
                          : const Icon(Icons.upload_rounded),
                      onTap: _flushing ? null : _flush,
                    ),
                    if (!kIsWeb)
                      ListTile(
                        key: const Key('debug-export'),
                        title: const Text('导出数据库'),
                        subtitle: const Text('给 tool/analytics_report.py 汇总'),
                        trailing: const Icon(Icons.ios_share_rounded),
                        onTap: _export,
                      ),
                    SwitchListTile.adaptive(
                      key: const Key('debug-fail'),
                      title: const Text('模拟上报失败（返回 503）'),
                      subtitle: const Text('观察退避重试：5 s、10 s、20 s…'),
                      value: service.collector.failUploads,
                      onChanged: (v) =>
                          setState(() => service.collector.failUploads = v),
                    ),
                  ],
                ),
                _Caption('最近上报'),
                InsetGroup(
                  children: [
                    if (snap == null || snap.uploads.isEmpty)
                      const _Empty('还没有上报记录')
                    else
                      for (final u in snap.uploads) _UploadRow(u),
                  ],
                ),
                _Caption('待上报队列（最新 30 条）'),
                InsetGroup(
                  children: [
                    if (snap == null || snap.pending.isEmpty)
                      const _Empty('队列是空的')
                    else
                      for (final e in snap.pending) _EventRow(e),
                  ],
                ),
                _Caption('分析 · 近 7 日阅读时长（分钟）'),
                if (snap != null) _ReadingBars(snap.reading),
                _Caption('分析 · 打开 → 读过半 → 读完（近 7 日）'),
                if (snap != null) _Funnel(snap.funnel),
                _Caption('分析 · 列表曝光与点击（近 7 日）'),
                if (snap != null)
                  InsetGroup(
                    children: [
                      if (snap.ctr.isEmpty)
                        const _Empty('还没有曝光数据')
                      else
                        for (final (surface, imp, open) in snap.ctr)
                          _Kv(
                            surface,
                            '曝光 $imp · 打开 $open'
                            '${imp > 0 ? ' · ${(open / imp * 100).toStringAsFixed(1)}%' : ''}',
                          ),
                    ],
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(32, 16, 32, 0),
                  child: Text(
                    '口径：会话在后台超过 30 秒后切分；阅读时长只计前台可见且 '
                    '60 秒内有交互的时间；曝光 = 卡片可见 ≥ 50% 且持续 ≥ 500 ms，'
                    '同一会话同一列表只计一次。分析基于模拟服务端已收到的事件。',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: GleanColors.label2,
                    ),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 22, 32, 7),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, color: GleanColors.label2),
    ),
  );
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v);

  final String k;
  final String v;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    child: Row(
      children: [
        Text(k, style: const TextStyle(fontSize: 15)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            v,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, color: GleanColors.label2),
          ),
        ),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(text, style: TextStyle(color: GleanColors.label2)),
  );
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, {this.color});

  final String label;
  final int? value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: GleanColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            '${value ?? 0}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color ?? GleanColors.label,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: GleanColors.label2),
          ),
        ],
      ),
    ),
  );
}

String _time(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

class _UploadRow extends StatelessWidget {
  const _UploadRow(this.u);

  final UploadRecord u;

  @override
  Widget build(BuildContext context) {
    final color = u.ok ? GleanColors.green : GleanColors.red;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              u.httpStatus?.toString() ?? '离线',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('${u.count} 条', style: const TextStyle(fontSize: 15)),
          const Spacer(),
          Text(
            '${_time(u.sentAt)} · ${u.durationMs ?? 0} ms',
            style: TextStyle(fontSize: 13, color: GleanColors.label2),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.e);

  final QueuedEvent e;

  @override
  Widget build(BuildContext context) {
    final business = {
      for (final MapEntry(:key, :value) in e.params.entries)
        if (!const {
          'device_id',
          'app_version',
          'platform',
          'network',
        }.contains(key))
          key: value,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                e.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              Text(
                '#${e.seq} · ${_time(e.ts)}'
                '${e.attempts > 0 ? ' · 重试 ${e.attempts}' : ''}',
                style: TextStyle(fontSize: 12, color: GleanColors.label2),
              ),
            ],
          ),
          if (business.isNotEmpty)
            Text(
              '$business',
              style: TextStyle(
                fontSize: 12,
                color: GleanColors.label2,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadingBars extends StatelessWidget {
  const _ReadingBars(this.days);

  final List<(DateTime, double, int)> days;

  @override
  Widget build(BuildContext context) {
    final top = days.fold(0.0, (m, d) => d.$2 > m ? d.$2 : m);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
      decoration: BoxDecoration(
        color: GleanColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox(
        height: 130,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (day, minutes, _) in days)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      minutes.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 10.5),
                    ),
                    const SizedBox(height: 4),
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: top == 0 ? 0 : minutes / top),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (context, f, _) => Container(
                        width: 18,
                        height: 4 + 80 * f,
                        decoration: BoxDecoration(
                          color: GleanColors.tint,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${day.month}/${day.day}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: GleanColors.label2,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Funnel extends StatelessWidget {
  const _Funnel(this.f);

  final (int, int, int) f;

  @override
  Widget build(BuildContext context) {
    final (opened, half, done) = f;
    Widget bar(String label, int n) {
      final share = opened == 0 ? 0.0 : n / opened;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(label, style: const TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    width: 6 + (box.maxWidth - 6) * share,
                    height: 18,
                    decoration: BoxDecoration(
                      color: GleanColors.tint.withValues(
                        alpha: 0.35 + 0.65 * share,
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 70,
              child: Text(
                '$n · ${(share * 100).toStringAsFixed(0)}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GleanColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [bar('打开', opened), bar('读过半', half), bar('读完', done)],
      ),
    );
  }
}
