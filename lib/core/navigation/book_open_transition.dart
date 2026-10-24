import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../design/layout.dart';

/// Where a book-opening transition starts (the tapped cover on the list)
/// and what its first page shows.
class BookOpening {
  const BookOpening({
    required this.origin,
    required this.originRadius,
    required this.cover,
    required this.titlePage,
    required this.paper,
    this.onLifted,
  });

  /// The list cover's rect in global coordinates.
  final Rect origin;
  final double originRadius;

  /// Draws the cover picture at a corner radius.
  final Widget Function(double radius) cover;

  /// The top of the page being opened, laid out for the full screen width;
  /// the first page shows it scaled to the book. When the page has grown
  /// to the screen it is exactly the reader's own header.
  final Widget titlePage;

  /// Page colour (the reader theme's background).
  final Color paper;

  /// True while the book is off the list (the list hides its own cover so
  /// there is only one), false once it has landed back or the page closed.
  final ValueChanged<bool>? onLifted;

  static const forward = Duration(milliseconds: 1100);
  static const reverse = Duration(milliseconds: 850);
}

/// Opening the reader like a paper book, driven by the route animation
/// (0 = list, 1 = reader), so a back swipe closes it under the finger and a
/// cancelled swipe springs it open again. Prototype with the same numbers:
/// docs/design/book-open-v2.html.
///
///  1. lift (0-0.28): the book rises off the list with a slight turn that
///     shows its spine and page block, and comes to the middle, the list
///     dimming behind it;
///  2. open (0.20-0.60): the cover swings open on the spine (the back is
///     the endpaper); two flyleaves follow it over a beat later
///     (0.26-0.64, 0.30-0.66), revealing the title page; all of them lie
///     flat before the zoom starts. The book narrows as it opens and slides
///     right so the spread stays centred;
///  3. zoom (0.68-0.95): the first page grows to fill the screen, the open
///     left side leaving. The first page is the reader's own title page
///     scaled down, so at full size it is the reader's top, pixel for
///     pixel;
///  4. reveal (0.95-1): the reader (title page plus the text below it)
///     takes over; the top does not change, the text fades in.
///
/// The reader stays mounted the whole time (only its opacity changes), so
/// its state survives the transition.
class BookOpenTransition extends StatefulWidget {
  const BookOpenTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.book,
    required this.child,
  });

  final Animation<double> animation;

  /// Another page pushed on top of the reader: the usual parallax.
  final Animation<double> secondaryAnimation;

  final BookOpening book;
  final Widget child;

  static const lift = Interval(0, 0.28, curve: Curves.easeOutCubic);
  static const open = Interval(0.2, 0.6, curve: Curves.easeInOutSine);
  static const leaf1 = Interval(0.26, 0.64, curve: Curves.easeInOutSine);
  static const leaf2 = Interval(0.3, 0.66, curve: Curves.easeInOutSine);
  static const zoom = Interval(0.68, 0.95, curve: Curves.easeInOutCubic);
  static const reveal = Interval(0.95, 1);

  /// Page width relative to the screen width (and its cap), closed and
  /// open: the book narrows as it opens so the spread (two pages, spine on
  /// the centre line) fits on the screen with a margin. 3:4.
  static const closedWidthFactor = 0.58;
  static const maxClosedWidth = 280.0;
  static const openWidthFactor = 0.45;
  static const maxOpenWidth = 220.0;
  static const perspective = 1 / 2200;
  static const maxTilt = 14 * pi / 180;
  static const dim = 0.3;
  static const leafPaper = Color(0xFFF7F1E5);

  @override
  State<BookOpenTransition> createState() => _BookOpenTransitionState();
}

class _BookOpenTransitionState extends State<BookOpenTransition> {
  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onStatus);
    widget.book.onLifted?.call(true);
  }

  @override
  void didUpdateWidget(BookOpenTransition old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) {
      old.animation.removeStatusListener(_onStatus);
      widget.animation.addStatusListener(_onStatus);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    widget.book.onLifted?.call(false);
    super.dispose();
  }

  void _onStatus(AnimationStatus status) =>
      widget.book.onLifted?.call(status != AnimationStatus.dismissed);

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: widget.secondaryAnimation.drive(
        Tween(begin: Offset.zero, end: const Offset(-0.3, 0)),
      ),
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: widget.animation,
          child: widget.child,
          builder: (context, child) => _frame(box.biggest, child!),
        ),
      ),
    );
  }

  Widget _frame(Size screen, Widget reader) {
    final raw = widget.animation.value;
    // No overall ease: each phase has its own curve, so the opening keeps
    // its full length; a back gesture maps the finger straight onto it.
    final t = raw;
    final lift = BookOpenTransition.lift.transform(t);
    final open = BookOpenTransition.open.transform(t);
    final zoom = BookOpenTransition.zoom.transform(t);
    final reveal = BookOpenTransition.reveal.transform(t);
    final done = t >= 1;

    final bw = lerpDouble(
      min(
        screen.width * BookOpenTransition.closedWidthFactor,
        BookOpenTransition.maxClosedWidth,
      ),
      min(
        screen.width * BookOpenTransition.openWidthFactor,
        BookOpenTransition.maxOpenWidth,
      ),
      open,
    )!;
    final bh = bw * 4 / 3;
    // The spine moves to the centre line as the book opens, so the spread
    // is centred: left page to the left of it, right page to the right.
    final closed = Rect.fromLTWH(
      (screen.width - bw) / 2 + bw / 2 * open,
      screen.height * 0.45 - bh / 2,
      bw,
      bh,
    );
    final held = Rect.lerp(widget.book.origin, closed, lift)!;
    // The page grows into the reader's text column: the whole screen on a
    // phone, the centred reading width in a wide window.
    final column = Layout.readingWidth(screen.width);
    final target = Rect.fromLTWH(
      (screen.width - column) / 2,
      0,
      column,
      screen.height,
    );
    final page = zoom > 0 ? Rect.lerp(held, target, zoom)! : held;
    final radius = lerpDouble(widget.book.originRadius, 6, lift)! * (1 - zoom);
    // A slight turn while the book is in hand shows the spine and pages.
    final tilt =
        -BookOpenTransition.maxTilt * sin(pi * (t / 0.4).clamp(0.0, 1.0));
    final leftGone = zoom > 0 && page.left <= target.left + 0.5;
    final spread = page.width * open * (1 - zoom);

    return Stack(
      children: [
        // Every layer stays in the tree at every value (empty when not
        // needed), so the reader keeps its place, and its state.
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              color: Colors.black.withValues(
                alpha: BookOpenTransition.dim * lift * (done ? 0 : 1),
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: done
              ? Rect.zero
              : Rect.fromLTRB(
                  page.left - spread,
                  page.top,
                  page.right,
                  page.bottom,
                ),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: 0.5 * lift * (1 - zoom),
                    ),
                    blurRadius: 40,
                    offset: const Offset(0, 30),
                    spreadRadius: -12,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: done ? Rect.zero : page,
          child: IgnorePointer(
            child: done
                ? const SizedBox.shrink()
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, BookOpenTransition.perspective)
                      ..rotateY(tilt),
                    // Text needs a Material above it outside a Scaffold.
                    child: Material(
                      type: MaterialType.transparency,
                      child: Stack(
                        clipBehavior: Clip.none,
                        fit: StackFit.expand,
                        children: [
                          _FirstPage(
                            book: widget.book,
                            screenWidth: column,
                            radius: radius,
                            gutter: sin(open * pi / 2) * (1 - zoom),
                          ),
                          if (!leftGone) ..._turningLayers(t, open, radius),
                          // The page block's edge, showing while closed.
                          Positioned(
                            right: -6,
                            top: page.height * 0.02,
                            bottom: page.height * 0.02,
                            width: 6,
                            child: Opacity(
                              opacity: 1 - open,
                              child: const _PageBlock(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        // The reader dissolves in over the (opaque) title page.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !done,
            child: Opacity(opacity: done ? 1 : reveal, child: reader),
          ),
        ),
      ],
    );
  }

  /// The cover and the two flyleaves, painted bottom to top by how high
  /// each stands above the page it lies on, as in a real book: on the
  /// right the more upright one is above (the cover on top while closed);
  /// once over the spine the flatter one is below, so a leaf still in the
  /// air passes over the cover's back instead of through it.
  List<Widget> _turningLayers(double t, double open, double radius) {
    // depth: 0 innermost leaf .. 2 the cover.
    double height(double degrees, int depth) => degrees <= 90
        ? degrees + depth * 0.01
        : 180 - degrees + (2 - depth) * 0.01;
    final cover = open * 180;
    final leaf1 = BookOpenTransition.leaf1.transform(t) * 180;
    final leaf2 = BookOpenTransition.leaf2.transform(t) * 180;
    final layers = [
      (height(leaf2, 0), _leaf(leaf2)),
      (height(leaf1, 1), _leaf(leaf1)),
      (height(cover, 2), _cover(cover, radius)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, layer) in layers) layer];
  }

  /// A leaf (or the cover) turned [degrees] about its left edge.
  Widget _turned(double degrees, Widget child) => Transform(
    alignment: Alignment.centerLeft,
    transform: Matrix4.identity()
      ..setEntry(3, 2, BookOpenTransition.perspective)
      // Positive: the free edge comes up towards the viewer (Flutter's z
      // points into the screen), then over to the left.
      ..rotateY(degrees * pi / 180),
    child: child,
  );

  Widget _leaf(double degrees) => _turned(
    degrees,
    const DecoratedBox(
      decoration: BoxDecoration(
        color: BookOpenTransition.leafPaper,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(2),
          right: Radius.circular(6),
        ),
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color(0xFFE9E1D2), BookOpenTransition.leafPaper],
          stops: [0, 0.12],
        ),
      ),
    ),
  );

  Widget _cover(double degrees, double radius) {
    final back = degrees > 90;
    // Light falls off as the cover turns away from the viewer.
    final shade = back ? 0.35 * (1 - (degrees - 90) / 90) : 0.45 * degrees / 90;
    final face = back
        ? _Endpaper(paper: widget.book.paper)
        : Stack(
            fit: StackFit.expand,
            children: [
              widget.book.cover(radius),
              // Spine crease and a sheen along it.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0x59000000),
                      Color(0x59000000),
                      Color(0x14FFFFFF),
                      Color(0x00FFFFFF),
                    ],
                    stops: [0, 0.04, 0.05, 0.12],
                  ),
                ),
              ),
            ],
          );
    return _turned(
      degrees,
      Transform(
        // The back face is drawn mirrored; turn it so it reads right.
        alignment: Alignment.center,
        transform: Matrix4.identity()..rotateY(back ? pi : 0),
        child: ClipRRect(
          borderRadius: BorderRadius.horizontal(
            left: const Radius.circular(2),
            right: Radius.circular(radius),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              face,
              ColoredBox(color: Colors.black.withValues(alpha: shade)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The first page the cover reveals: the reader's title page, laid out at
/// the screen width and scaled to the page, on the theme's paper.
class _FirstPage extends StatelessWidget {
  const _FirstPage({
    required this.book,
    required this.screenWidth,
    required this.radius,
    required this.gutter,
  });

  final BookOpening book;
  final double screenWidth;
  final double radius;

  /// Strength of the shade along the spine.
  final double gutter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => ClipRRect(
        borderRadius: BorderRadius.horizontal(
          left: const Radius.circular(2),
          right: Radius.circular(radius),
        ),
        child: ColoredBox(
          color: book.paper,
          child: Stack(
            children: [
              OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: screenWidth,
                maxWidth: screenWidth,
                maxHeight: double.infinity,
                child: Transform.scale(
                  alignment: Alignment.topLeft,
                  scale: box.maxWidth / screenWidth,
                  child: book.titlePage,
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: box.maxWidth * 0.18,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.28 * gutter),
                        Colors.black.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inside of the cover, which becomes the left page of the open spread:
/// the same paper as the right page, with the binding's shade along the
/// spine (its right edge) and a faint imprint.
class _Endpaper extends StatelessWidget {
  const _Endpaper({required this.paper});

  final Color paper;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: paper,
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color.lerp(paper, Colors.black, 0.12)!, paper],
          stops: const [0, 0.18],
        ),
      ),
      child: Center(
        child: Text(
          '拾读',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 6,
            color: Color.lerp(paper, const Color(0xFF24574A), 0.22),
          ),
        ),
      ),
    );
  }
}

/// Edge of the pages, seen beside the closed cover.
class _PageBlock extends StatelessWidget {
  const _PageBlock();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          tileMode: TileMode.repeated,
          colors: const [Color(0xFFF3EDE1), Color(0xFFD8CFBF)],
          stops: const [0.7, 1],
          transform: const _Stripes(),
        ),
      ),
    );
  }
}

/// Repeats the page-block gradient every 2 px.
class _Stripes extends GradientTransform {
  const _Stripes();

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.diagonal3Values(1, 2 / bounds.height, 1);
}
