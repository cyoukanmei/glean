import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../design/glean_theme.dart';
import 'cover_catalog.dart';

/// Article cover: the bundled picture when there is one ([image]), otherwise
/// a book jacket drawn in code (a deep colour picked from the article id, a
/// darker spine, a small caps band on top and the serif title).
///
/// Landscape pictures simply fill the box at every size.
/// One layout covers every size, so a Hero flight between a square list
/// thumbnail and the wide reader header stays continuous: as the box gets
/// wider than it is tall, the jacket shrinks into a portrait "book" standing
/// in the middle of a softer backdrop of the same colour. Below about 56 px
/// the title would be unreadable, so the jacket shows its initial instead.
class ArticleCover extends StatelessWidget {
  const ArticleCover({
    super.key,
    required this.seed,
    required this.title,
    this.band,
    this.footer,
    this.image,
    this.borderRadius = BorderRadius.zero,
  });

  /// Bundled picture; portrait ones (book illustrations) behave like the
  /// jacket and stand as a book in wide boxes.
  final CoverImage? image;

  /// Picks the colour; the article id, so a cover never changes.
  final String seed;
  final String title;

  /// Small caps line above the title (author or "GLEAN · 科技").
  final String? band;

  /// Line at the bottom of large covers.
  final String? footer;
  final BorderRadius borderRadius;

  static const jackets = [
    Color(0xFF1E3A5F), // navy
    Color(0xFF7C2D12), // oxblood
    Color(0xFF14532D), // forest
    Color(0xFF0F766E), // teal
    Color(0xFF9A5B13), // ochre
    Color(0xFF5B21B6), // plum
    Color(0xFF334155), // slate
    Color(0xFF881337), // burgundy
    Color(0xFF1E40AF), // ink blue
    Color(0xFF4D5B1F), // olive
  ];

  /// Stable across runs and platforms (unlike String.hashCode).
  static Color colorFor(String seed) {
    var h = 0x811C9DC5;
    for (final c in seed.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return jackets[h % jackets.length];
  }

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    if (image != null && !image.portrait) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: ColoredBox(color: image.dominant, child: _Picture(image)),
      );
    }
    final color = image?.dominant ?? colorFor(seed);
    return ClipRRect(
      borderRadius: borderRadius,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final h = box.maxHeight;
          // 0 for square boxes (the jacket is the whole cover), 1 from the
          // reader header's ~1.2 aspect up (a book standing on a backdrop).
          final t = ((w / h - 1.02) / 0.16).clamp(0.0, 1.0);
          final bookH = h * lerpDouble(1, 0.6, t)!;
          final bookW = lerpDouble(w, bookH * (image?.aspect ?? 0.7), t)!;
          final corner = lerpDouble(0, 4, t)!;
          final book = image == null
              ? _Jacket(
                  color: color,
                  title: title,
                  band: band,
                  footer: footer,
                  width: bookW,
                  height: bookH,
                  corner: corner,
                )
              : ClipRRect(
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(corner / 2),
                    right: Radius.circular(corner),
                  ),
                  child: SizedBox(
                    width: bookW,
                    height: bookH,
                    child: _Picture(image),
                  ),
                );
          if (t == 0) return book;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.2),
                radius: 1.1,
                colors: [
                  Color.lerp(color, Colors.white, 0.55)!,
                  Color.lerp(color, Colors.white, 0.3)!,
                ],
              ),
            ),
            child: Align(
              alignment: Alignment(0, lerpDouble(0, -0.1, t)!),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35 * t),
                      blurRadius: 30,
                      offset: const Offset(0, 16),
                      spreadRadius: -6,
                    ),
                  ],
                ),
                child: book,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Jacket extends StatelessWidget {
  const _Jacket({
    required this.color,
    required this.title,
    required this.band,
    required this.footer,
    required this.width,
    required this.height,
    required this.corner,
  });

  final Color color;
  final String title;
  final String? band;
  final String? footer;
  final double width;
  final double height;
  final double corner;

  static const _ink = Color(0xFFFBF7EE);

  /// Shrinks [size] until the title's longest word fits on one line, so a
  /// narrow jacket never breaks "Adventures" in the middle.
  double _fitTitle(double size, double available) {
    if (available <= 0) return size;
    final longest = title
        .split(RegExp(r'\s+'))
        .fold('', (a, b) => b.length > a.length ? b : a);
    final painter = TextPainter(
      text: TextSpan(
        text: longest,
        style: TextStyle(
          fontFamily: serifFamily,
          fontFamilyFallback: serifFallback,
          fontSize: size,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width <= available ? size : max(7.0, size * available / width);
  }

  @override
  Widget build(BuildContext context) {
    final s = min(width, height);
    final spine = max(3.0, s * 0.07);
    final pad = s * 0.1;
    final titleSize = _fitTitle(
      (s * 0.145).clamp(9.0, 26.0),
      width - spine - pad * 2,
    );
    return ClipRRect(
      borderRadius: BorderRadius.horizontal(
        left: Radius.circular(corner / 2),
        right: Radius.circular(corner),
      ),
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(color, Colors.white, 0.08)!, color],
            ),
          ),
          child: Stack(
            children: [
              // Spine shadow and the crease next to it.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: spine,
                child: const ColoredBox(color: Color(0x2E000000)),
              ),
              Positioned(
                left: spine,
                top: 0,
                bottom: 0,
                width: 1,
                child: const ColoredBox(color: Color(0x1FFFFFFF)),
              ),
              if (s < 56)
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(left: spine),
                    child: Text(
                      title.isEmpty ? '' : title.characters.first,
                      style: TextStyle(
                        fontFamily: serifFamily,
                        fontFamilyFallback: serifFallback,
                        fontSize: s * 0.55,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: _ink,
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: EdgeInsets.fromLTRB(spine + pad, pad, pad, pad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (band != null && s >= 90) ...[
                        Text(
                          band!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: (s * 0.06).clamp(7.0, 11.0),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                            color: _ink.withValues(alpha: 0.78),
                          ),
                        ),
                        SizedBox(height: s * 0.04),
                        Container(
                          height: 1,
                          width: s * 0.25,
                          color: _ink.withValues(alpha: 0.4),
                        ),
                      ],
                      // Takes what is left; a long title is cut, never overflows.
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Text(
                            title,
                            maxLines: s >= 140 ? 4 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: serifFamily,
                              fontFamilyFallback: serifFallback,
                              fontSize: titleSize,
                              fontWeight: FontWeight.w700,
                              height: 1.12,
                              color: _ink,
                            ),
                          ),
                        ),
                      ),
                      if (footer != null && s >= 140) ...[
                        SizedBox(height: s * 0.05),
                        Text(
                          footer!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: (s * 0.055).clamp(8.0, 11.0),
                            letterSpacing: 0.6,
                            color: _ink.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bundled picture, decoded only as large as it is drawn: a 56 pt list
/// thumbnail does not need the full 720 px bitmap (1.4-2.8 MB in memory,
/// over 10x the pixels it shows). Sizes snap to a few buckets so a growing
/// Hero flight re-decodes at most twice; the previous bitmap stays up
/// meanwhile (gaplessPlayback).
class _Picture extends StatelessWidget {
  const _Picture(this.image);

  final CoverImage image;

  /// Decode widths in device pixels; anything larger uses the full picture.
  static const buckets = [256, 512];

  /// Width to decode [image] at to fill [box] with BoxFit.cover, or null
  /// for full size.
  static int? decodeWidth(Size box, double aspect, double dpr) {
    if (!box.isFinite) return null;
    // Cover scales the picture until it fills the box on both axes.
    final need = max(box.width, box.height * aspect) * dpr;
    for (final b in buckets) {
      if (need <= b) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => Image(
        image: ResizeImage.resizeIfNeeded(
          decodeWidth(
            box.biggest,
            image.aspect,
            MediaQuery.devicePixelRatioOf(context),
          ),
          null,
          AssetImage(image.asset),
        ),
        fit: BoxFit.cover,
        // Book art keeps its top (title, faces) when cropped to a square.
        alignment: image.portrait ? const Alignment(0, -0.4) : Alignment.center,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      ),
    );
  }
}
