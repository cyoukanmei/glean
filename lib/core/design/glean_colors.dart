import 'package:flutter/material.dart';

/// Design tokens from docs/design/ui-reference.html (iOS system palette plus
/// the brand teal / mint / gold from the designer's asset pack).
abstract final class GleanColors {
  // iOS system surfaces and text.
  static const background = Color(0xFFF2F2F7);
  static const card = Color(0xFFFFFFFF);
  static const label = Color(0xFF1C1C1E);
  static const label2 = Color(0x9E3C3C43); // rgba(60,60,67,.62)
  static const label3 = Color(0x523C3C43); // rgba(60,60,67,.32)
  static const separator = Color(0x243C3C43); // rgba(60,60,67,.14)
  static const fill = Color(0x1F767680); // rgba(118,118,128,.12)
  static const fill2 = Color(0x14767680); // rgba(118,118,128,.08)

  // Brand.
  static const tint = Color(0xFF0F766E);
  static const tintBright = Color(0xFF14B8A6);
  static const tintDeep = Color(0xFF134E4A);
  static const mintSoft = Color(0xFFECFDF8);
  static const mintLight = Color(0xFF5EEAD4);
  static const gold = Color(0xFFF5A623);
  static const goldSoft = Color(0xFFFEF3C7);
  static const goldInk = Color(0xFF9A6200);
  static const red = Color(0xFFFF3B30);
  static const green = Color(0xFF34C759);

  // Offline strip.
  static const warnBg = Color(0xFFFFF7E6);
  static const warnInk = Color(0xFF8A5A00);

  /// Difficulty badge (background, ink) per level 1..3.
  static const levelBadge = {
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
    accent: GleanColors.tint,
    chipBg: GleanColors.mintSoft,
    bar: Color(0xC8FFFFFF),
    barInk: GleanColors.label,
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
    accent: GleanColors.mintLight,
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
