import 'dart:math';

import 'package:flutter/material.dart';

/// Article cover: the designer's category illustration filling its box
/// (square thumbnails show it whole; the wide reader header crops top and
/// bottom of the cream margin and fades into the page below).
///
/// Only four images exist and each is 720 px, so they are decoded once at
/// full size and shared by every card; no per-size decoding means nothing
/// re-decodes while the cover morphs during a Hero flight.
///
/// Unknown categories fall back to a gradient from the palette key
/// (`g0`..`g7`) plus a category icon.
class ArticleCover extends StatelessWidget {
  const ArticleCover({
    super.key,
    required this.palette,
    required this.category,
    this.borderRadius = BorderRadius.zero,
  });

  final String palette;
  final String category;
  final BorderRadius borderRadius;

  /// Asset and its sampled background colour, used to fill letterboxing.
  static const _illustrations = {
    'tech': ('assets/covers/tech.webp', Color(0xFFFCF7EB)),
    'business': ('assets/covers/business.webp', Color(0xFFFAF5EB)),
    'culture': ('assets/covers/culture.webp', Color(0xFFFBF3E5)),
    'daily': ('assets/covers/daily.webp', Color(0xFFFAF2E3)),
  };

  static const _gradients = [
    [Color(0xFF0F766E), Color(0xFF5EEAD4)],
    [Color(0xFF1D4ED8), Color(0xFF93C5FD)],
    [Color(0xFF7C3AED), Color(0xFFC4B5FD)],
    [Color(0xFFB45309), Color(0xFFFCD34D)],
    [Color(0xFFBE123C), Color(0xFFFDA4AF)],
    [Color(0xFF15803D), Color(0xFF86EFAC)],
    [Color(0xFF334155), Color(0xFF94A3B8)],
    [Color(0xFFC2410C), Color(0xFFFDBA74)],
  ];

  @override
  Widget build(BuildContext context) {
    final illustration = _illustrations[category];
    return ClipRRect(
      borderRadius: borderRadius,
      child: illustration == null
          ? _fallback()
          : ColoredBox(
              color: illustration.$2,
              child: Image.asset(
                illustration.$1,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
    );
  }

  Widget _fallback() {
    final index = int.tryParse(palette.substring(1)) ?? 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradients[index % _gradients.length],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) => Center(
          child: Icon(
            Icons.article_rounded,
            size: min(box.maxWidth, box.maxHeight) * 0.4,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}
