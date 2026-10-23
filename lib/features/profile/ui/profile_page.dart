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
            LargeTitle(
              title: '我的',
              eyebrow: user == null ? '未登录' : '$name · 已登录',
              trailing: Semantics(
                button: true,
                label: '编辑资料',
                child: PressableScale(
                  key: const Key('profile-avatar-button'),
                  onTap: user == null ? null : _editProfile,
                  child: Hero(
                    tag: 'me-avatar',
                    child: UserAvatar(user: user, size: 44),
                  ),
                ),
              ),
            ),
            if (user?.bio case final bio? when bio.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  bio,
                  style: const TextStyle(
                    fontSize: 15,
                    color: GleanColors.label2,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            _GoalCard(stats: stats, goalMinutes: user?.dailyGoalMinutes ?? 15),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _Tile(value: '${stats?.finished ?? 0}', label: '读完文章'),
                  const SizedBox(width: 10),
                  _Tile(value: '${stats?.words ?? 0}', label: '收藏生词'),
                  const SizedBox(width: 10),
                  _Tile(
                    value: _hours(stats?.totalMs ?? 0),
                    unit: (stats?.totalMs ?? 0) < 3600000 ? 'min' : 'h',
                    label: '累计阅读',
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(32, 22, 32, 7),
              child: Text(
                '设置',
                style: TextStyle(fontSize: 13, color: GleanColors.label2),
              ),
            ),
            InsetGroup(
              dividerIndent: 58,
              children: [
                _Cell(
                  icon: Icons.text_fields_rounded,
                  color: GleanColors.tint,
                  title: '阅读设置',
                  value:
                      '${settings.followSystem ? '跟随系统' : settings.theme.label}'
                      ' · ${settings.fontSize.toStringAsFixed(settings.fontSize % 1 == 0 ? 0 : 1)}',
                  onTap: () => ReaderSettingsSheet.show(context),
                ),
                _Cell(
                  icon: Icons.download_done_rounded,
                  color: const Color(0xFF34C759),
                  title: '离线内容',
                  value: '${stats?.articles ?? 0} 篇 · 全部可离线阅读',
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
        borderRadius: BorderRadius.circular(22),
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
                    style: const TextStyle(
                      fontSize: 11,
                      color: GleanColors.label2,
                    ),
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
                    const Icon(
                      Icons.local_fire_department_rounded,
                      size: 15,
                      color: GleanColors.gold,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      (s?.streak ?? 0) > 0
                          ? '连续 ${s!.streak} 天'
                          : '今天读一篇，开始连续打卡',
                      style: const TextStyle(
                        fontSize: 13,
                        color: GleanColors.label2,
                      ),
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
            style: const TextStyle(fontSize: 11, color: GleanColors.label2),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label, this.unit});

  final String value;
  final String? unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: GleanColors.card,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                text: value,
                children: [
                  if (unit != null)
                    TextSpan(
                      text: ' $unit',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: GleanColors.label2),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final Color color;
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
            const SizedBox(width: 16),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 16.5)),
            const Spacer(),
            Flexible(
              flex: 3,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, color: GleanColors.label2),
              ),
            ),
            if (onTap != null)
              const Icon(
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
