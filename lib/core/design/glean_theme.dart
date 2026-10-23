import 'package:flutter/material.dart';

import 'glean_colors.dart';

/// Serif family for article text: "New York" on iOS, Noto Serif on Android.
const serifFamily = 'serif';
const serifFallback = ['New York', 'Georgia', 'Noto Serif', 'Songti SC'];

/// App theme in the iOS idiom: system grouped background, no ink ripples
/// (presses scale instead, see PressableScale), bouncing scroll everywhere
/// and the iOS type ramp (large title 34, headline 17 semibold, body 17).
///
/// Built from the current palette, so it follows [GleanColors.dark].
ThemeData gleanTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: GleanColors.tint,
    brightness: GleanColors.dark ? Brightness.dark : Brightness.light,
    primary: GleanColors.tint,
    surface: GleanColors.card,
    onSurface: GleanColors.label,
  );
  final ink = GleanColors.label;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: GleanColors.background,
    splashFactory: NoSplash.splashFactory,
    highlightColor: GleanColors.fill2,
    dividerColor: GleanColors.separator,
    textTheme: TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.15,
        color: ink,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: ink,
      ),
      titleSmall: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 17, height: 1.45, color: ink),
      bodyMedium: TextStyle(fontSize: 15, height: 1.45, color: ink),
      bodySmall: TextStyle(
        fontSize: 13,
        height: 1.4,
        color: GleanColors.label2,
      ),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: GleanColors.label2,
      ),
      labelSmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: GleanColors.label2,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: GleanColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xEB1E1E20),
      contentTextStyle: const TextStyle(fontSize: 15, color: Colors.white),
      actionTextColor: GleanColors.mintLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: GleanColors.sheet,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: GleanColors.label3,
      dragHandleSize: Size(36, 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: GleanColors.tint,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// iOS overscroll: content bounces at the edges instead of glowing.
class GleanScrollBehavior extends MaterialScrollBehavior {
  const GleanScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
