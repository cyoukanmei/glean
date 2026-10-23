import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../articles/data/article_repository.dart';
import '../../articles/ui/cover_hero.dart';
import '../../articles/ui/labels.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.article, required this.surface});

  /// Already loaded by the list, so the header (and the cover Hero's
  /// destination) is built on the very first frame.
  final ArticleSummary article;

  /// List the article was opened from; must match its card's Hero tag.
  final String surface;

  /// Body entrance: waits for the page transition (the cover lands first),
  /// pauses briefly, then fades the text up into place.
  static const entranceDelay = Duration(milliseconds: 80);
  static const entranceDuration = Duration(milliseconds: 280);
  static const entranceRise = 12.0;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with SingleTickerProviderStateMixin {
  static const _headerHeight = 220.0;

  late final Future<List<String>> _paragraphs = ref
      .read(articleRepositoryProvider)
      .paragraphs(widget.article.id);

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: ReaderPage.entranceDuration,
  );
  late final Animation<double> _entranceCurve = _entrance.drive(
    CurveTween(curve: Curves.easeOutCubic),
  );

  final _transitionDone = Completer<void>();
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    _startEntrance();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation == _routeAnimation) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = animation;
    if (animation == null) {
      _completeTransition();
      return;
    }
    // On the first build the route's animation is a proxy still parented to
    // an always-complete placeholder; the real transition is attached later
    // (the proxy reports that as a status change). So listen instead of
    // trusting the current status, and only check it after the first frame
    // for routes pushed without a transition.
    animation.addStatusListener(_onRouteStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && animation.isCompleted) _completeTransition();
    });
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status.isCompleted) _completeTransition();
  }

  void _completeTransition() {
    if (!_transitionDone.isCompleted) _transitionDone.complete();
  }

  /// Plays once per page: a back swipe that is cancelled midway completes
  /// the route animation again but must not replay the entrance.
  Future<void> _startEntrance() async {
    await Future.wait([_transitionDone.future, _paragraphs]);
    await Future<void>.delayed(ReaderPage.entranceDelay);
    if (mounted) _entrance.forward();
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: _headerHeight + MediaQuery.paddingOf(context).top,
                  child: CoverHero(
                    article: article,
                    surface: widget.surface,
                    borderRadius: CoverHero.headerRadius,
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: IconButton.filledTonal(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const BackButtonIcon(),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                    ),
                  ),
                ),
              ],
            ),
            FadeTransition(
              key: const Key('reader-body'),
              opacity: _entranceCurve,
              child: AnimatedBuilder(
                animation: _entranceCurve,
                builder: (context, child) => Transform.translate(
                  offset: Offset(
                    0,
                    ReaderPage.entranceRise * (1 - _entranceCurve.value),
                  ),
                  child: child,
                ),
                child: _Body(article: article, paragraphs: _paragraphs),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.article, required this.paragraphs});

  final ArticleSummary article;
  final Future<List<String>> paragraphs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text(article.title, style: theme.textTheme.headlineSmall),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            articleMeta(article.category, article.level, article.wordCount),
            style: theme.textTheme.labelMedium,
          ),
        ),
        FutureBuilder(
          future: paragraphs,
          builder: (context, snap) {
            final list = snap.data ?? const <String>[];
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        p,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
