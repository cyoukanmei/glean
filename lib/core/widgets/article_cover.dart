import 'dart:math';

import 'package:flutter/material.dart';

/// Article cover drawn from a palette key (`g0`..`g7`) plus a category icon.
///
/// Covers ship as data, not images, so they render offline and decode free.
/// The icon scales with the cover's shorter side, so the cover morphs
/// smoothly when it flies between a list thumbnail and the reader header.
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

  static const _icons = {
    'tech': Icons.memory_rounded,
    'business': Icons.storefront_rounded,
    'culture': Icons.theater_comedy_rounded,
    'daily': Icons.wb_sunny_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final index = int.tryParse(palette.substring(1)) ?? 0;
    final colors = _gradients[index % _gradients.length];
    return ClipRRect(
      borderRadius: borderRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, box) => Center(
            child: Icon(
              _icons[category] ?? Icons.article_rounded,
              size: min(box.maxWidth, box.maxHeight) * 0.4,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }
}
