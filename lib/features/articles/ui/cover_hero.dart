import 'package:flutter/material.dart';

import '../../../core/widgets/article_cover.dart';
import '../../../core/widgets/cover_catalog.dart';
import '../data/article_repository.dart';
import 'labels.dart';

/// Article cover shared between a list card and the reader header.
///
/// * Follows the finger on swipe-back (`transitionOnUserGestures`).
/// * Flies in a straight line ([RectTween]) instead of Material's default
///   arc, so a gesture-driven flight tracks the horizontal drag.
/// * Morphs the corner radius between the two ends during the flight.
class CoverHero extends StatelessWidget {
  const CoverHero({
    super.key,
    required this.article,
    required this.surface,
    required this.borderRadius,
  });

  final ArticleSummary article;

  /// Which list the card lives in (e.g. a category tab). The same article can
  /// sit in several kept-alive tabs at once, so the tag must include it.
  final String surface;
  final double borderRadius;

  static const listRadius = 16.0;
  static const headerRadius = 0.0;

  static Object tagFor(String surface, String articleId) =>
      'cover-$surface-$articleId';

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.maybeOf(context);
    return Hero(
      tag: tagFor(surface, article.id),
      transitionOnUserGestures: true,
      // Same curves as SwipeBackPageRoute's slide, so cover and page move
      // together; both turn linear while a back gesture drives the route.
      curve: _GestureAwareCurve(Curves.easeOutCubic, navigator),
      reverseCurve: _GestureAwareCurve(Curves.easeInCubic, navigator),
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: _shuttle,
      child: _cover(borderRadius),
    );
  }

  Widget _cover(double radius) => ArticleCover(
    seed: article.id,
    title: article.title,
    band:
        article.author?.toUpperCase() ??
        'GLEAN · ${categoryLabels[article.category] ?? article.category}',
    footer: article.author != null
        ? '拾读 · 名著'
        : '${levelLabels[article.level] ?? ''} · ${article.wordCount} 词',
    image: CoverCatalog.instance[article.id],
    borderRadius: BorderRadius.circular(radius),
  );

  /// `animation` is the route animation: 0 = list, 1 = reader, for both push
  /// and pop, so one lerp covers both directions.
  Widget _shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    // The list end's corner radius (a shelf book is squarer than a feed
    // thumbnail); the shuttle comes from the reader's hero on push.
    final list =
        (direction == HeroFlightDirection.push ? fromContext : toContext)
            .widget;
    final start = list is Hero && list.child is ArticleCover
        ? (list.child as ArticleCover).borderRadius.topLeft.x
        : listRadius;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) =>
          _cover(_lerp(start, headerRadius, animation.value)),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// [curve], except linear while a user gesture drives the navigator.
///
/// A Hero picks its curve once, when the flight starts, but the page
/// transition switches to linear for the duration of a back gesture. Reading
/// the flag per frame keeps the flying cover locked to the page.
class _GestureAwareCurve extends Curve {
  const _GestureAwareCurve(this.curve, this.navigator);

  final Curve curve;
  final NavigatorState? navigator;

  @override
  double transformInternal(double t) =>
      (navigator?.userGestureInProgress ?? false) ? t : curve.transform(t);
}
