import 'package:flutter/material.dart';

/// Colour schemes the user can pick in 我的 → 主题配色.
enum ColorTheme {
  /// Cream paper and deep green, from the splash illustration (default).
  paper('纸感', '米白 · 墨绿'),

  /// iOS white and teal.
  classic('经典', '白 · 青绿');

  const ColorTheme(this.label, this.subtitle);

  final String label;
  final String subtitle;
}

/// Design tokens: neutral surfaces and text, brand greens and gold.
///
/// Everything follows [theme] (paper / classic) and [dark] (set by the app
/// root from the settings) and is read at build time; the root repaints the
/// tree when either changes.
abstract final class GleanColors {
  static ColorTheme theme = ColorTheme.paper;

  /// Whether the dark variants are in effect.
  static bool dark = false;

  static bool get _paper => theme == ColorTheme.paper;

  /// Picks by theme and brightness: paper light, paper dark, classic light,
  /// classic dark.
  static Color _p(int pl, int pd, int cl, int cd) =>
      Color(_paper ? (dark ? pd : pl) : (dark ? cd : cl));

  // Surfaces and text (grouped style).
  static Color get background =>
      _p(0xFFFAF1E2, 0xFF15130F, 0xFFF2F2F7, 0xFF000000);

  /// Cards and grouped lists. Paper uses a sage tint from the leaves in the
  /// illustration rather than a near-white, which looked bleached on cream.
  static Color get card => _p(0xFFEEEEDF, 0xFF23271F, 0xFFFFFFFF, 0xFF1C1C1E);

  /// Bottom sheets: the page colour on paper (a sage sheet reads as a card),
  /// the card colour on classic.
  static Color get sheet => _paper ? background : card;

  /// Article lists laid straight on the page with hairlines between rows,
  /// like a book's contents page (paper), or as one inset group (classic).
  static bool get listsOnPaper => _paper;
  static Color get label => _p(0xFF2A2620, 0xFFF3ECDF, 0xFF1C1C1E, 0xFFFFFFFF);
  static Color get label2 => _p(0xA0473D30, 0x99EDE3D2, 0x9E3C3C43, 0x99EBEBF5);
  static Color get label3 => _p(0x58473D30, 0x4DEDE3D2, 0x523C3C43, 0x4DEBEBF5);
  static Color get separator =>
      _p(0x2E6B5B45, 0x80544C40, 0x243C3C43, 0x99545458);
  static Color get fill => _p(0x1F8A7A60, 0x3D7A6E5C, 0x1F767680, 0x3D767680);
  static Color get fill2 => _p(0x148A7A60, 0x2E7A6E5C, 0x14767680, 0x2E767680);

  /// Secondary body text (meanings, thoughts): darker than [label2].
  static Color get ink2 => _p(0xFF4A4238, 0xFFD6CDBD, 0xFF3A3A3C, 0xFFD1D1D6);

  /// Frosted bars and floating controls.
  static Color get barGlass =>
      _p(0xD9FCF6EA, 0xC7221F1A, 0xC7F9F9FB, 0xC71C1C1E);

  // Brand.
  static Color get tint => _p(0xFF24574A, 0xFF4E9A80, 0xFF0F766E, 0xFF0F766E);
  static Color get tintBright =>
      _p(0xFF3C8A70, 0xFF6DB79C, 0xFF14B8A6, 0xFF14B8A6);
  static Color get tintDeep =>
      _p(0xFF173B32, 0xFF173B32, 0xFF134E4A, 0xFF134E4A);
  static Color get mintSoft =>
      _p(0xFFE6EDE1, 0xFF1C2E28, 0xFFECFDF8, 0xFF0E3330);
  static Color get mintLight =>
      _p(0xFFA8D5C0, 0xFFA8D5C0, 0xFF5EEAD4, 0xFF5EEAD4);
  static Color get gold => _p(0xFFD9A23E, 0xFFE8B95A, 0xFFF5A623, 0xFFF5A623);
  static Color get goldSoft =>
      _p(0xFFF6E7C8, 0xFF3A2E14, 0xFFFEF3C7, 0xFF3A2C0A);
  static Color get goldInk =>
      _p(0xFF8A5E12, 0xFFF0C774, 0xFF9A6200, 0xFFFBBF24);
  static const red = Color(0xFFFF3B30);
  static const green = Color(0xFF34C759);

  // Offline strip.
  static Color get warnBg => _p(0xFFF7E6C4, 0xFF332605, 0xFFFFF7E6, 0xFF332605);
  static Color get warnInk =>
      _p(0xFF7A5210, 0xFFFBD38D, 0xFF8A5A00, 0xFFFBD38D);

  /// Difficulty badge (background, ink) per level 1..3.
  static Map<int, (Color, Color)> get levelBadge => dark
      ? const {
          1: (Color(0xFF12301C), Color(0xFF86EFAC)),
          2: (Color(0xFF0C2B3D), Color(0xFF7DD3FC)),
          3: (Color(0xFF3A2C0A), Color(0xFFFCD34D)),
        }
      : const {
          1: (Color(0xFFDCFCE7), Color(0xFF15803D)),
          2: (Color(0xFFE0F2FE), Color(0xFF0369A1)),
          3: (Color(0xFFFEF3C7), Color(0xFFB45309)),
        };
}

/// Reader page theme: paper, eye-care (sepia) or night.
enum ReaderTheme {
  paper(
    label: '纸白',
    background: Color(0xFFFBF7EE),
    text: Color(0xFF2A2723),
    title: Color(0xFF1C1C1E),
    secondary: Color(0x9E3C3C43),
    accent: Color(0xFF0F766E),
    chipBg: Color(0xFFECFDF8),
    bar: Color(0xC8FFFFFF),
    barInk: Color(0xFF1C1C1E),
  ),
  sepia(
    label: '护眼',
    background: Color(0xFFF6EBD3),
    text: Color(0xFF4A3B26),
    title: Color(0xFF3A2C18),
    secondary: Color(0x995B4A2E),
    accent: Color(0xFF8A6A2F),
    chipBg: Color(0xFFEDDDB8),
    bar: Color(0xC8FBF3E2),
    barInk: Color(0xFF3A2C18),
  ),
  night(
    label: '夜间',
    background: Color(0xFF141414),
    text: Color(0xFFD9D2C3),
    title: Color(0xFFF2ECE0),
    secondary: Color(0x99D9D2C3),
    accent: Color(0xFF5EEAD4),
    chipBg: Color(0x2914B8A6),
    bar: Color(0xB82C2C2E),
    barInk: Color(0xFFEEEEEE),
  );

  const ReaderTheme({
    required this.label,
    required this.background,
    required this.text,
    required this.title,
    required this.secondary,
    required this.accent,
    required this.chipBg,
    required this.bar,
    required this.barInk,
  });

  final String label;
  final Color background;
  final Color text;
  final Color title;
  final Color secondary;
  final Color accent;
  final Color chipBg;

  /// Translucent fill for floating glass controls.
  final Color bar;
  final Color barInk;

  bool get isDark => this == night;
}
