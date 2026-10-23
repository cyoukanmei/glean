import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/design/glean_colors.dart';

enum LineSpacing {
  compact('紧凑', 1.5),
  standard('标准', 1.72),
  loose('宽松', 1.95);

  const LineSpacing(this.label, this.height);

  final String label;
  final double height;
}

/// Typography and colour choices from the reader's Aa sheet.
class ReaderSettings {
  const ReaderSettings({
    this.fontSize = defaultFontSize,
    this.spacing = LineSpacing.standard,
    this.theme = ReaderTheme.paper,
    this.followSystem = true,
  });

  static const defaultFontSize = 18.5;
  static const minFontSize = 14.0;
  static const maxFontSize = 24.0;

  final double fontSize;
  final LineSpacing spacing;
  final ReaderTheme theme;

  /// Switch to the night theme while the system is in dark mode.
  final bool followSystem;

  /// How tall the text lays out relative to the defaults. Saved positions
  /// carry it, so a position saved at another size restores by paragraph
  /// anchor instead of raw pixels.
  double get layoutScale =>
      fontSize *
      spacing.height /
      (defaultFontSize * LineSpacing.standard.height);

  ReaderTheme effectiveTheme({required bool systemDark}) =>
      followSystem && systemDark ? ReaderTheme.night : theme;

  ReaderSettings copyWith({
    double? fontSize,
    LineSpacing? spacing,
    ReaderTheme? theme,
    bool? followSystem,
  }) => ReaderSettings(
    fontSize: fontSize ?? this.fontSize,
    spacing: spacing ?? this.spacing,
    theme: theme ?? this.theme,
    followSystem: followSystem ?? this.followSystem,
  );
}

class ReaderSettingsNotifier extends Notifier<ReaderSettings> {
  static const _font = 'reader.fontSize';
  static const _spacing = 'reader.spacing';
  static const _theme = 'reader.theme';
  static const _follow = 'reader.followSystem';

  @override
  ReaderSettings build() {
    final prefs = ref.watch(prefsProvider);
    T? byName<T extends Enum>(List<T> values, String? name) =>
        values.where((v) => v.name == name).firstOrNull;
    return ReaderSettings(
      fontSize: (prefs.getDouble(_font) ?? ReaderSettings.defaultFontSize)
          .clamp(ReaderSettings.minFontSize, ReaderSettings.maxFontSize),
      spacing:
          byName(LineSpacing.values, prefs.getString(_spacing)) ??
          LineSpacing.standard,
      theme:
          byName(ReaderTheme.values, prefs.getString(_theme)) ??
          ReaderTheme.paper,
      followSystem: prefs.getBool(_follow) ?? true,
    );
  }

  void setFontSize(double size) {
    state = state.copyWith(fontSize: size);
    ref.read(prefsProvider).setDouble(_font, size);
  }

  void setSpacing(LineSpacing spacing) {
    state = state.copyWith(spacing: spacing);
    ref.read(prefsProvider).setString(_spacing, spacing.name);
  }

  /// Picking a theme by hand turns "follow system" off, otherwise a dark
  /// system would keep overriding the choice.
  void setTheme(ReaderTheme theme) {
    state = state.copyWith(theme: theme, followSystem: false);
    ref.read(prefsProvider)
      ..setString(_theme, theme.name)
      ..setBool(_follow, false);
  }

  void setFollowSystem(bool follow) {
    state = state.copyWith(followSystem: follow);
    ref.read(prefsProvider).setBool(_follow, follow);
  }
}

final readerSettingsProvider =
    NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
      ReaderSettingsNotifier.new,
    );
