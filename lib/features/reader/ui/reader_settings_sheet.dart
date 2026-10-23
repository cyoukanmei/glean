import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/glean_theme.dart';
import '../../../core/design/ios_widgets.dart';
import '../application/reader_settings.dart';

/// The Aa sheet: font size, line spacing, theme, follow system dark mode.
/// Every change applies live to the page behind the sheet.
class ReaderSettingsSheet extends ConsumerWidget {
  const ReaderSettingsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: GleanColors.sheet,
    barrierColor: const Color(0x47000000),
    builder: (_) => const ReaderSettingsSheet(),
  );

  static void _track(String setting, Object value) =>
      Analytics.track('reader_settings', {'setting': setting, 'value': value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    Widget caption(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: GleanColors.label2),
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '阅读设置',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            caption('字号'),
            Row(
              children: [
                const Text('A', style: TextStyle(fontSize: 14)),
                Expanded(
                  child: CupertinoSlider(
                    key: const Key('font-size-slider'),
                    value: s.fontSize,
                    min: ReaderSettings.minFontSize,
                    max: ReaderSettings.maxFontSize,
                    divisions: 20,
                    activeColor: GleanColors.tint,
                    onChanged: notifier.setFontSize,
                    onChangeEnd: (v) => _track('font_size', v),
                  ),
                ),
                const Text('A', style: TextStyle(fontSize: 22)),
              ],
            ),
            caption('行距'),
            IosSegmented<LineSpacing>(
              value: s.spacing,
              items: {for (final l in LineSpacing.values) l: l.label},
              onChanged: (l) {
                notifier.setSpacing(l);
                _track('line_spacing', l.name);
              },
            ),
            caption('主题'),
            Row(
              children: [
                for (final (i, t) in ReaderTheme.values.indexed) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(
                    child: _ThemeTile(
                      theme: t,
                      selected: !s.followSystem && s.theme == t,
                      onTap: () {
                        notifier.setTheme(t);
                        _track('theme', t.name);
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            DecoratedBox(
              decoration: BoxDecoration(
                color: GleanColors.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.dark_mode_rounded,
                      size: 20,
                      color: GleanColors.tint,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('跟随系统深色模式', style: TextStyle(fontSize: 16)),
                    ),
                    CupertinoSwitch(
                      value: s.followSystem,
                      activeTrackColor: GleanColors.green,
                      onChanged: (v) {
                        notifier.setFollowSystem(v);
                        _track('follow_system', v);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final ReaderTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = theme == ReaderTheme.paper ? Colors.white : theme.background;
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        key: Key('theme-${theme.name}'),
        duration: const Duration(milliseconds: 200),
        height: 76,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? GleanColors.tint : GleanColors.separator,
            width: selected ? 2 : 0.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Aa',
              style: TextStyle(
                fontFamily: serifFamily,
                fontFamilyFallback: serifFallback,
                fontSize: 22,
                color: theme.title,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              theme.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
