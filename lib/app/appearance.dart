import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics/analytics.dart';
import '../core/design/glean_colors.dart';
import 'providers.dart';

enum Appearance {
  system('跟随系统'),
  light('浅色'),
  dark('深色');

  const Appearance(this.label);

  final String label;
}

/// 外观 setting, persisted.
class AppearanceNotifier extends Notifier<Appearance> {
  static const _key = 'appearance';

  @override
  Appearance build() {
    final saved = ref.watch(prefsProvider).getString(_key);
    return Appearance.values.where((a) => a.name == saved).firstOrNull ??
        Appearance.system;
  }

  void set(Appearance a) {
    if (a == state) return;
    state = a;
    ref.read(prefsProvider).setString(_key, a.name);
    Analytics.track('appearance_set', {'value': a.name});
  }
}

final appearanceProvider = NotifierProvider<AppearanceNotifier, Appearance>(
  AppearanceNotifier.new,
);

/// 主题配色 setting (paper / classic), persisted; paper by default.
class ColorThemeNotifier extends Notifier<ColorTheme> {
  static const _key = 'color_theme';

  @override
  ColorTheme build() {
    final saved = ref.watch(prefsProvider).getString(_key);
    return ColorTheme.values.where((t) => t.name == saved).firstOrNull ??
        ColorTheme.paper;
  }

  void set(ColorTheme t) {
    if (t == state) return;
    state = t;
    ref.read(prefsProvider).setString(_key, t.name);
    Analytics.track('appearance_set', {'value': 'theme_${t.name}'});
  }
}

final colorThemeProvider = NotifierProvider<ColorThemeNotifier, ColorTheme>(
  ColorThemeNotifier.new,
);

/// Marks every element under [context] dirty, so widgets that read the
/// palette directly (const ones included) repaint after a light/dark switch
/// without losing any state or navigation.
void rebuildAllChildren(BuildContext context) {
  void rebuild(Element e) {
    e.markNeedsBuild();
    e.visitChildren(rebuild);
  }

  (context as Element).visitChildren(rebuild);
}
