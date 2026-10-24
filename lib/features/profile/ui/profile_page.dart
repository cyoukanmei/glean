import 'package:clock/clock.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import '../../../core/design/progress_ring.dart';
import '../../auth/application/auth.dart';
import '../../reader/application/reader_settings.dart';
import '../../reader/data/reading_time_repository.dart';
import '../../reader/ui/reader_settings_sheet.dart';
import '../../../core/navigation/swipe_back_route.dart';
import '../application/profile_stats.dart';
import '../../sync/ui/sync_page.dart';
import '../../../app/appearance.dart';
import '../application/reminder.dart';
import '../../library/data/marks_repository.dart';
import '../../library/ui/library_page.dart';
import '../../../app/home_tab.dart';
import '../../coread/ui/coread_page.dart';
import 'analytics_debug_page.dart';
import 'perf_page.dart';
import 'edit_profile_page.dart';
import 'user_avatar.dart';

/// 我的: today's reading goal, this week's check-ins, totals, settings.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  ProfileStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = ref.read(currentUserIdProvider);
    final time = ref.read(readingTimeRepositoryProvider);
    final now = clock.now();
    final from = ReadingTimeRepository.localDay(
      now.subtract(ProfileStats.lookback).millisecondsSinceEpoch,
    );
    final (byDay, finished, words, total, articles) = await (
      time.activeMsByDay(userId, fromDay: from),
      ref.read(progressRepositoryProvider).finishedCount(userId),
      ref.read(vocabRepositoryProvider).list(userId).then((l) => l.length),
      time.totalActiveMsAll(userId),
      ref.read(articleRepositoryProvider).count(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _stats = ProfileStats.from(
        msByDay: byDay,
        today: now,
        finished: finished,
        words: words,
        totalMs: total,
        articles: articles,
      );
    });
  }

  Future<void> _confirmLogout() async {
    final ok = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        message: const Text('退出后，本机数据仍会保留，下次登录可继续。'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出登录'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
      ),
    );
    if (ok ?? false) await ref.read(authProvider.notifier).logout();
  }

  void _editProfile() => Navigator.of(context).push(
    SwipeBackPageRoute<void>(
      settings: const RouteSettings(name: '/me/edit'),
      builder: (_) => const EditProfilePage(),
    ),
  );

  static String _hours(int ms) {
    final minutes = ms ~/ 60000;
    if (minutes < 60) return '$minutes';
    return (minutes / 60).toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(progressRevisionProvider, (_, _) => _load());
    ref.listen(vocabRevisionProvider, (_, _) => _load());
    final user = ref.watch(authProvider);
    final settings = ref.watch(readerSettingsProvider);
    final stats = _stats;
    final name = user?.name ?? '游客';
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.only(
            top: 8,
            bottom: MediaQuery.paddingOf(context).bottom + 24,
          ),
          children: [
            const LargeTitle(title: '我的'),
            const SizedBox(height: 12),
            _ProfileCard(
              name: name,
              bio: switch (user?.bio) {
                final bio? when bio.isNotEmpty => bio,
                _ when user == null => '未登录',
                _ => '每天读一点',
              },
              avatar: Semantics(
                button: true,
                label: '编辑资料',
                child: PressableScale(
                  key: const Key('profile-avatar-button'),
                  onTap: user == null ? null : _editProfile,
                  child: Hero(
                    tag: 'me-avatar',
                    child: UserAvatar(user: user, size: 60),
                  ),
                ),
              ),
              onEdit: user == null ? null : _editProfile,
              stats: [
                _Stat(value: '${stats?.finished ?? 0}', label: '读完文章'),
                _Stat(value: '${stats?.words ?? 0}', label: '收藏生词'),
                _Stat(
                  value: _hours(stats?.totalMs ?? 0),
                  unit: (stats?.totalMs ?? 0) < 3600000 ? 'min' : 'h',
                  label: '累计阅读',
                ),
                _Stat(value: '${stats?.streak ?? 0}', label: '连续天数'),
              ],
            ),
            const SizedBox(height: 16),
            const _QuickEntries(),
            const SizedBox(height: 12),
            _GoalCard(stats: stats, goalMinutes: user?.dailyGoalMinutes ?? 15),
            const _GroupLabel('阅读'),
            InsetGroup(
              dividerIndent: 56,
              children: [
                _Cell(
                  icon: Icons.text_fields_rounded,
                  title: '阅读设置',
                  value:
                      '${settings.followSystem ? '跟随系统' : settings.theme.label}'
                      ' · ${settings.fontSize.toStringAsFixed(settings.fontSize % 1 == 0 ? 0 : 1)}',
                  onTap: () => ReaderSettingsSheet.show(context),
                ),
                const _ReminderCell(),
                _Cell(
                  icon: Icons.download_done_rounded,
                  title: '离线内容',
                  value: '${stats?.articles ?? 0} 篇 · 全部可离线阅读',
                ),
              ],
            ),
            const _GroupLabel('通用'),
            InsetGroup(
              dividerIndent: 56,
              children: [
                const _ColorThemeCell(),
                const _AppearanceCell(),
                const _SyncCell(),
                _Cell(
                  key: const Key('open-perf'),
                  icon: Icons.speed_rounded,
                  title: '性能监测',
                  value: '帧耗时 · 启动 · 图片缓存',
                  onTap: () => Navigator.of(context).push(
                    SwipeBackPageRoute<void>(
                      settings: const RouteSettings(name: '/me/perf'),
                      builder: (_) => const PerfPage(),
                    ),
                  ),
                ),
                _Cell(
                  key: const Key('open-analytics-debug'),
                  icon: Icons.insights_rounded,
                  title: '埋点调试面板',
                  value: '队列 · 上报 · 分析',
                  onTap: () => Navigator.of(context).push(
                    SwipeBackPageRoute<void>(
                      settings: const RouteSettings(name: '/me/analytics'),
                      builder: (_) => const AnalyticsDebugPage(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            InsetGroup(
              children: [
                GestureDetector(
                  key: const Key('logout'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _confirmLogout,
                  child: const SizedBox(
                    height: 46,
                    child: Center(
                      child: Text(
                        '退出登录',
                        style: TextStyle(
                          fontSize: 16.5,
                          color: GleanColors.red,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.stats, required this.goalMinutes});

  final ProfileStats? stats;
  final int goalMinutes;

  static const _days = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final minutes = (s?.todayMs ?? 0) ~/ 60000;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: GleanColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: GleanColors.cardShadow,
      ),
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            key: const Key('goal-ring'),
            tween: Tween(begin: 0, end: s?.goalProgress(goalMinutes) ?? 0),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => ProgressRing(
              value: v,
              size: 104,
              strokeWidth: 10,
              color: GleanColors.tint,
              trackColor: GleanColors.fill,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$minutes',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                    ),
                  ),
                  Text(
                    '/ $goalMinutes 分钟',
                    style: TextStyle(fontSize: 11, color: GleanColors.label2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '今日目标',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 15,
                      color: GleanColors.gold,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      (s?.streak ?? 0) > 0
                          ? '连续 ${s!.streak} 天'
                          : '今天读一篇，开始连续打卡',
                      style: TextStyle(fontSize: 13, color: GleanColors.label2),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < 7; i++)
                      _DayDot(
                        label: _days[i],
                        done: s?.week[i] ?? false,
                        today: s?.todayIndex == i,
                        future: s != null && i > s.todayIndex,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.label,
    required this.done,
    required this.today,
    required this.future,
  });

  final String label;
  final bool done;
  final bool today;
  final bool future;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: future ? 0.4 : 1,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? GleanColors.tint : GleanColors.fill,
              border: today && !done
                  ? Border.all(color: GleanColors.gold, width: 2)
                  : null,
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: GleanColors.label2),
          ),
        ],
      ),
    );
  }
}

/// The profile card: avatar, name, bio and 编辑资料 over four stats, on the
/// same deep-green gradient as the continue-reading card.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.bio,
    required this.avatar,
    required this.stats,
    this.onEdit,
  });

  final String name;
  final String bio;
  final Widget avatar;
  final List<Widget> stats;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GleanColors.tint, GleanColors.tintDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: GleanColors.tintDeep.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
            spreadRadius: -14,
          ),
        ],
      ),
      child: Stack(
        children: [
          // A soft light in the corner.
          Positioned(
            right: -70,
            top: -90,
            child: Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x26FFFFFF), Color(0x00FFFFFF)],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0x66FFFFFF),
                          width: 2,
                        ),
                      ),
                      child: avatar,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            bio,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xB3FFFFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onEdit != null)
                      PressableScale(
                        key: const Key('profile-edit'),
                        onTap: onEdit,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x1FFFFFFF),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0x59FFFFFF),
                              width: 0.8,
                            ),
                          ),
                          child: const Text(
                            '编辑资料',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                IntrinsicHeight(
                  child: Row(
                    children: [
                      for (final (i, s) in stats.indexed) ...[
                        if (i > 0)
                          const VerticalDivider(
                            width: 1,
                            thickness: 0.6,
                            indent: 6,
                            endIndent: 6,
                            color: Color(0x33FFFFFF),
                          ),
                        Expanded(child: s),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A number over a label, centred in its column of the profile card.
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.unit});

  final String value;
  final String? unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text.rich(
          TextSpan(
            text: value,
            children: [
              if (unit != null)
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: Color(0xA6FFFFFF)),
        ),
      ],
    );
  }
}

/// Small caption above a settings group.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 22, 32, 7),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: GleanColors.label2),
      ),
    );
  }
}

/// Settings icon: the same quiet ink glyph on a soft tile for every row,
/// instead of a different bright colour each.
class _CellIcon extends StatelessWidget {
  const _CellIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: GleanColors.background,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 18, color: GleanColors.ink2),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            const SizedBox(width: 14),
            _CellIcon(icon),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 12),
            // Value sits against the chevron, like iOS Settings.
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 15, color: GleanColors.label2),
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: GleanColors.label3,
              ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// 同步 row: live summary of the sync state, opens the sync page.
class _SyncCell extends ConsumerStatefulWidget {
  const _SyncCell();

  @override
  ConsumerState<_SyncCell> createState() => _SyncCellState();
}

class _SyncCellState extends ConsumerState<_SyncCell> {
  late final _sync = ref.read(syncServiceProvider);
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _sync?.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    _sync?.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final p = await _sync?.pending();
    if (mounted && p != null) setState(() => _pending = p.$1 + p.$2);
  }

  @override
  Widget build(BuildContext context) {
    // Local writes change the pending count without a sync event.
    ref.listen(progressRevisionProvider, (_, _) => _refresh());
    ref.listen(vocabRevisionProvider, (_, _) => _refresh());
    final online = ref.watch(onlineProvider).value ?? true;
    return _Cell(
      key: const Key('open-sync'),
      icon: Icons.sync_rounded,
      title: '同步',
      value: syncSummary(_sync, online: online, pending: _pending),
      onTap: () => Navigator.of(context).push(
        SwipeBackPageRoute<void>(
          settings: const RouteSettings(name: '/me/sync'),
          builder: (_) => const SyncPage(),
        ),
      ),
    );
  }
}

/// 每日阅读提醒: a switch, plus the time (tap to change).
class _ReminderCell extends ConsumerWidget {
  const _ReminderCell();

  Future<void> _pickTime(BuildContext context, WidgetRef ref) async {
    final current = ref.read(reminderProvider);
    var picked = current.time;
    final ok = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => Container(
        height: 300,
        color: GleanColors.card,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Row(
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    key: const Key('reminder-time-done'),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('完成'),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  initialDateTime: DateTime(
                    2026,
                    1,
                    1,
                    picked.hour,
                    picked.minute,
                  ),
                  onDateTimeChanged: (d) =>
                      picked = TimeOfDay(hour: d.hour, minute: d.minute),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if ((ok ?? false) && context.mounted) await _enable(context, ref, picked);
  }

  Future<void> _enable(
    BuildContext context,
    WidgetRef ref,
    TimeOfDay time,
  ) async {
    final ok = await ref.read(reminderProvider.notifier).enable(time);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('通知权限没有打开，可以在系统设置里允许拾读发通知')),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(reminderProvider);
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          const SizedBox(width: 14),
          const _CellIcon(Icons.notifications_none_rounded),
          const SizedBox(width: 12),
          const Text('每日阅读提醒', style: TextStyle(fontSize: 16)),
          const Spacer(),
          GestureDetector(
            key: const Key('reminder-time'),
            onTap: () => _pickTime(context, ref),
            child: Text(
              r.label,
              style: TextStyle(
                fontSize: 15,
                color: r.enabled ? GleanColors.tint : GleanColors.label2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CupertinoSwitch(
            key: const Key('reminder-switch'),
            value: r.enabled,
            activeTrackColor: GleanColors.tint,
            onChanged: (on) => on
                ? _enable(context, ref, r.time)
                : ref.read(reminderProvider.notifier).disable(),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// 外观: follow the system, or always light / dark.
class _AppearanceCell extends ConsumerWidget {
  const _AppearanceCell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appearanceProvider);
    return _Cell(
      key: const Key('open-appearance'),
      icon: Icons.contrast_rounded,
      title: '外观',
      value: current.label,
      onTap: () async {
        final picked = await showCupertinoModalPopup<Appearance>(
          context: context,
          builder: (context) => CupertinoActionSheet(
            title: const Text('外观'),
            actions: [
              for (final a in Appearance.values)
                CupertinoActionSheetAction(
                  key: Key('appearance-${a.name}'),
                  isDefaultAction: a == current,
                  onPressed: () => Navigator.pop(context, a),
                  child: Text(a.label),
                ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ),
        );
        if (picked != null) ref.read(appearanceProvider.notifier).set(picked);
      },
    );
  }
}

/// 主题配色: paper (cream and deep green) or classic (white and teal).
class _ColorThemeCell extends ConsumerWidget {
  const _ColorThemeCell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(colorThemeProvider);
    return _Cell(
      key: const Key('open-color-theme'),
      icon: Icons.palette_outlined,
      title: '主题配色',
      value: current.label,
      onTap: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: GleanColors.card,
        builder: (_) => const _ColorThemeSheet(),
      ),
    );
  }
}

class _ColorThemeSheet extends ConsumerWidget {
  const _ColorThemeSheet();

  /// Swatches shown on each tile: (page, card, accent) in light mode.
  static const _swatches = {
    ColorTheme.paper: (Color(0xFFFAF1E2), Color(0xFFFFFCF6), Color(0xFF24574A)),
    ColorTheme.classic: (
      Color(0xFFF2F2F7),
      Color(0xFFFFFFFF),
      Color(0xFF0F766E),
    ),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(colorThemeProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '主题配色',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: GleanColors.label,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final (i, t) in ColorTheme.values.indexed) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(
                    child: PressableScale(
                      key: Key('color-theme-${t.name}'),
                      onTap: () => ref.read(colorThemeProvider.notifier).set(t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _swatches[t]!.$1,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: t == current
                                ? _swatches[t]!.$3
                                : GleanColors.separator,
                            width: t == current ? 2.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: _swatches[t]!.$2,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: _swatches[t]!.$3,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Container(
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: _swatches[t]!.$3.withValues(
                                          alpha: 0.25,
                                        ),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              t.label,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _swatches[t]!.$3,
                              ),
                            ),
                            Text(
                              t.subtitle,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xA0473D30),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of shortcuts in one quiet line-icon style: 收藏, 稍后再读 and
/// 阅读历史 with live counts, and 我的动态 (社区 → 我的).
class _QuickEntries extends ConsumerStatefulWidget {
  const _QuickEntries();

  @override
  ConsumerState<_QuickEntries> createState() => _QuickEntriesState();
}

class _QuickEntriesState extends ConsumerState<_QuickEntries> {
  Map<MarkKind, int> _counts = const {};
  int _history = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(currentUserIdProvider);
    final (counts, history) = await (
      ref.read(marksRepositoryProvider).counts(user),
      ref.read(progressRepositoryProvider).history(user),
    ).wait;
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _history = history.length;
    });
  }

  void _open(LibrarySection s) => Navigator.of(context).push(
    SwipeBackPageRoute<void>(
      settings: RouteSettings(name: '/me/library/${s.name}'),
      builder: (_) => LibraryPage(initial: s),
    ),
  );

  void _openMine() {
    ref.read(coreadTabProvider.notifier).select(CoreadTab.mine);
    ref.read(homeTabProvider.notifier).go(HomeTab.community);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(marksRevisionProvider, (_, _) => _load());
    ref.listen(progressRevisionProvider, (_, _) => _load());
    Widget entry(
      String key,
      IconData icon,
      String label,
      int? count,
      VoidCallback onTap,
    ) => Expanded(
      child: PressableScale(
        key: Key(key),
        onTap: onTap,
        child: Column(
          children: [
            Icon(icon, size: 25, color: GleanColors.label),
            const SizedBox(height: 7),
            Text(label, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 1),
            Text(
              count == null ? '查看' : '$count',
              style: TextStyle(fontSize: 11, color: GleanColors.label2),
            ),
          ],
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 12),
      decoration: BoxDecoration(
        color: GleanColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: GleanColors.cardShadow,
      ),
      child: Row(
        children: [
          entry(
            'open-favorites',
            Icons.star_border_rounded,
            '收藏',
            _counts[MarkKind.favorite] ?? 0,
            () => _open(LibrarySection.favorite),
          ),
          entry(
            'open-later',
            Icons.schedule_rounded,
            '稍后再读',
            _counts[MarkKind.later] ?? 0,
            () => _open(LibrarySection.later),
          ),
          entry(
            'open-history',
            Icons.history_rounded,
            '阅读历史',
            _history,
            () => _open(LibrarySection.history),
          ),
          entry('open-my-posts', Icons.forum_outlined, '我的动态', null, _openMine),
        ],
      ),
    );
  }
}
