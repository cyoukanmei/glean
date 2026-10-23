import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import '../sync_service.dart';

/// Human summary of the sync state, shared by this page and 我的.
String syncSummary(SyncService? s, {required bool online, int pending = 0}) {
  if (s == null) return '未启用';
  if (s.running) return '同步中…';
  if (!online) return pending > 0 ? '离线 · $pending 项待同步' : '离线';
  if (s.last?.skipped == 'guest') return '登录后同步';
  if (s.last?.error != null) return '上次失败，稍后重试';
  if (pending > 0) return '$pending 项待同步';
  final at = s.lastOkAt;
  if (at == null) return '尚未同步';
  final ago = clock.now().difference(DateTime.fromMillisecondsSinceEpoch(at));
  if (ago.inMinutes < 1) return '已同步 · 刚刚';
  if (ago.inHours < 1) return '已同步 · ${ago.inMinutes} 分钟前';
  return '已同步 · ${ago.inHours} 小时前';
}

/// 同步: state, pending changes, a manual sync, the conflict log and the
/// rules, plus a demo button that edits the data as a second device would.
class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage>
    with SingleTickerProviderStateMixin {
  late final SyncService? _sync = ref.read(syncServiceProvider);
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  (int, int) _pending = (0, 0);

  @override
  void initState() {
    super.initState();
    _sync?.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    _sync?.removeListener(_changed);
    _spin.dispose();
    super.dispose();
  }

  Future<void> _changed() async {
    final s = _sync;
    if (s == null) return;
    s.running ? _spin.repeat() : _spin.animateTo(1).then((_) => _spin.reset());
    final pending = await s.pending();
    if (mounted) setState(() => _pending = pending);
  }

  Future<void> _syncNow() async {
    final r = await _sync!.sync();
    if (!mounted) return;
    final text = switch (r) {
      SyncResult(skipped: 'offline') => '当前离线，联网后会自动同步',
      SyncResult(skipped: 'guest') => '登录后才会同步',
      SyncResult(error: final e?) => '同步失败：$e',
      _ =>
        '上传 ${r.pushed} 项，下载 ${r.pulled} 项'
            '${r.conflicts.isEmpty ? '' : '，处理冲突 ${r.conflicts.length} 项'}',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _otherDevice() async {
    final user = ref.read(currentUserIdProvider);
    final changed = await _sync!.server.simulateOtherDevice(user);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            changed.isEmpty
                ? '服务端还没有你的数据，先同步一次'
                : '${changed.join('；')}。点「立即同步」拉下来',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final s = _sync;
    final online = ref.watch(onlineProvider).value ?? true;
    final (progress, words) = _pending;
    return Scaffold(
      appBar: AppBar(
        title: const Text('同步'),
        backgroundColor: GleanColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: s == null
          ? const Center(child: Text('同步未启用'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                const SizedBox(height: 16),
                Center(
                  child: RotationTransition(
                    turns: _spin,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: GleanColors.mintSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.sync_rounded,
                        size: 38,
                        color: GleanColors.tint,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    syncSummary(s, online: online, pending: progress + words),
                    key: const Key('sync-summary'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton(
                    key: const Key('sync-now'),
                    onPressed: s.running ? null : _syncNow,
                    child: const Text('立即同步'),
                  ),
                ),
                const _Caption('待上传'),
                InsetGroup(
                  children: [
                    _Row('阅读进度', '$progress 篇'),
                    _Row('生词', '$words 个'),
                    _Row('本机 id', s.deviceId),
                  ],
                ),
                const _Caption('最近处理的冲突'),
                InsetGroup(
                  children: [
                    if (s.conflictLog.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          '还没有冲突',
                          style: TextStyle(color: GleanColors.label2),
                        ),
                      )
                    else
                      for (final (at, text) in s.conflictLog.take(8))
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Text(
                            '${_hm(at)}  $text',
                            style: const TextStyle(fontSize: 14, height: 1.4),
                          ),
                        ),
                  ],
                ),
                const _Caption('规则'),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    '本地先写，改动标记为待同步；联网、回到前台、改动后几秒和每分钟'
                    '都会同步。上传时带上次看到的服务端版本号，版本不一致即为冲突：\n'
                    '· 阅读进度按字段合并：最远进度和「读完」只增不减，阅读位置跟最近'
                    '一次阅读；\n'
                    '· 生词按最后修改时间整条取新（last-write-wins），删除也是一次修改。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: GleanColors.label2,
                    ),
                  ),
                ),
                const _Caption('演示'),
                InsetGroup(
                  children: [
                    ListTile(
                      key: const Key('sync-other-device'),
                      leading: const Icon(Icons.tablet_mac_rounded),
                      title: const Text('模拟另一台设备修改'),
                      subtitle: const Text('在服务端改一个生词和一篇进度'),
                      onTap: _otherDevice,
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  static String _hm(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
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

class _Row extends StatelessWidget {
  const _Row(this.k, this.v);

  final String k;
  final String v;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        Text(k, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            v,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, color: GleanColors.label2),
          ),
        ),
      ],
    ),
  );
}
