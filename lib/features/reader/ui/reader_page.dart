import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/widgets/celebration.dart';
import '../../../core/widgets/state_illustration.dart';
import '../../articles/data/article_repository.dart';
import '../../articles/ui/cover_hero.dart';
import '../../articles/ui/labels.dart';
import '../application/reading_session.dart';
import '../data/progress_repository.dart';
import 'reading_progress_bar.dart';

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

  /// Session bookkeeping cadence (see [ReadingSession]).
  static const tickInterval = Duration(milliseconds: 250);

  /// Restoring the last position: skipped for tiny offsets; long jumps snap
  /// to one screen before the target and glide the rest.
  static const restoreMinOffset = 24.0;
  static const restoreGlide = Duration(milliseconds: 500);
  static const restoreHintFor = Duration(seconds: 3);

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

/// Everything the page needs before it can track and restore reading.
class _Loaded {
  const _Loaded(this.paragraphs, this.saved, this.priorActiveMs);

  final List<String> paragraphs;
  final ReadingProgress? saved;
  final int priorActiveMs;
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with TickerProviderStateMixin {
  static const _headerHeight = 220.0;

  /// Reading settings arrive later; positions already store the scale so a
  /// changed font size restores by paragraph anchor instead of pixels.
  static const _fontScale = 1.0;

  late final String _userId = ref.read(currentUserIdProvider);
  late final Future<_Loaded> _loaded = _load();

  /// Read in initState: dispose() must not touch `ref`.
  late final ProgressRevision _progressRevision;

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: ReaderPage.entranceDuration,
  );
  late final Animation<double> _entranceCurve = _entrance.drive(
    CurveTween(curve: Curves.easeOutCubic),
  );

  final _scroll = ScrollController();
  final _contentKey = GlobalKey();
  List<GlobalKey> _paragraphKeys = const [];
  final _progress = ValueNotifier<double>(0);

  final _transitionDone = Completer<void>();
  Animation<double>? _routeAnimation;

  ReadingSession? _session;
  Timer? _ticker;
  late final AppLifecycleListener _lifecycle;
  bool _foreground = true;

  bool _restoreHint = false;
  Timer? _restoreHintTimer;
  bool _celebrating = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _progressRevision = ref.read(progressRevisionProvider.notifier);
    _scroll.addListener(_onScroll);
    _lifecycle = AppLifecycleListener(
      onResume: () => _setForeground(true),
      onInactive: () => _setForeground(false),
    );
    _start();
  }

  Future<_Loaded> _load() async {
    final id = widget.article.id;
    final (paragraphs, saved, prior) = await (
      ref.read(articleRepositoryProvider).paragraphs(id),
      ref.read(progressRepositoryProvider).get(_userId, id),
      ref.read(readingTimeRepositoryProvider).totalActiveMs(_userId, id),
    ).wait;
    return _Loaded(paragraphs, saved, prior);
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

  /// Entrance plays once per page: a back swipe that is cancelled midway
  /// completes the route animation again but must not replay it. After the
  /// entrance the reader glides back to where it left off.
  Future<void> _start() async {
    final (loaded, _) = await (_loaded, _transitionDone.future).wait;
    if (!mounted) return;
    _session = ReadingSession(
      userId: _userId,
      articleId: widget.article.id,
      wordCount: widget.article.wordCount,
      sessionId: const Uuid().v4(),
      progress: ref.read(progressRepositoryProvider),
      time: ref.read(readingTimeRepositoryProvider),
      priorActiveMs: loaded.priorActiveMs,
      alreadyFinished: loaded.saved?.status == ReadingStatus.finished,
      onFinished: _celebrate,
    )..restoreMaxProgress(loaded.saved?.maxProgress ?? 0);
    _ticker = Timer.periodic(ReaderPage.tickInterval, (_) => _tick());

    await Future<void>.delayed(ReaderPage.entranceDelay);
    if (!mounted) return;
    await _entrance.forward();
    if (!mounted) return;
    // Record the first screen even without scrolling: a short article that
    // fits on screen is fully seen without a single scroll event.
    _onScroll();
    if (loaded.saved != null) await _restore(loaded.saved!);
  }

  void _tick() {
    final session = _session;
    if (session == null) return;
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    session.setActive(visible && _foreground);
    session.tick();
  }

  void _setForeground(bool foreground) {
    _foreground = foreground;
    // Flush right away: an inactive app may be killed without another tick.
    if (!foreground) _session?.flush();
  }

  void _onScroll() {
    final position = _currentPosition();
    if (position == null) return;
    _progress.value = position.progress;
    _session?.onPosition(position);
  }

  /// Paragraph tops and heights in scroll-content coordinates.
  List<(double top, double height)> _paragraphBoxes() {
    final content = _contentKey.currentContext?.findRenderObject();
    if (content is! RenderBox) return const [];
    return [
      for (final key in _paragraphKeys)
        if (key.currentContext?.findRenderObject() case final RenderBox box)
          (
            box.localToGlobal(Offset.zero, ancestor: content).dy,
            box.size.height,
          ),
    ];
  }

  ReadingPosition? _currentPosition() {
    if (!_scroll.hasClients) return null;
    final p = _scroll.position;
    final offset = p.pixels;
    final viewport = p.viewportDimension;
    final boxes = _paragraphBoxes();
    // Share of the article seen: measured to the end of the last paragraph,
    // so trailing space and the "done" footer appearing do not move it.
    // Short articles that fit on screen count as fully seen.
    final end = boxes.isEmpty
        ? p.maxScrollExtent + viewport
        : boxes.last.$1 + boxes.last.$2;
    final progress = end <= 0
        ? 0.0
        : ((offset + viewport) / end).clamp(0.0, 1.0);

    var para = 0;
    var delta = 0.0;
    for (var i = 0; i < boxes.length; i++) {
      final (top, height) = boxes[i];
      if (top > offset) break;
      para = i;
      delta = height <= 0 ? 0 : ((offset - top) / height).clamp(0.0, 1.0);
    }
    return ReadingPosition(
      scrollOffset: offset,
      anchorPara: para,
      anchorDelta: delta,
      fontScale: _fontScale,
      progress: progress.toDouble(),
    );
  }

  Future<void> _restore(ReadingProgress saved) async {
    if (!_scroll.hasClients) return;
    final pos = saved.position;
    var target = pos.scrollOffset;
    if ((pos.fontScale - _fontScale).abs() > 0.001) {
      final boxes = _paragraphBoxes();
      if (pos.anchorPara < boxes.length) {
        final (top, height) = boxes[pos.anchorPara];
        target = top + pos.anchorDelta * height;
      }
    }
    final p = _scroll.position;
    target = target.clamp(0.0, p.maxScrollExtent);
    if (target < ReaderPage.restoreMinOffset) return;

    if (target - p.pixels > p.viewportDimension * 3) {
      _scroll.jumpTo(target - p.viewportDimension);
    }
    setState(() => _restoreHint = true);
    _restoreHintTimer = Timer(ReaderPage.restoreHintFor, () {
      if (mounted) setState(() => _restoreHint = false);
    });
    await _scroll.animateTo(
      target,
      duration: ReaderPage.restoreGlide,
      curve: Curves.easeInOutCubic,
    );
  }

  void _backToTop() {
    _restoreHintTimer?.cancel();
    setState(() => _restoreHint = false);
    _scroll.animateTo(
      0,
      duration: ReaderPage.restoreGlide,
      curve: Curves.easeInOutCubic,
    );
  }

  void _celebrate() {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Analytics.track('article_finish', {'article_id': widget.article.id});
    setState(() {
      _celebrating = true;
      _finished = true;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _restoreHintTimer?.cancel();
    _lifecycle.dispose();
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    final session = _session;
    if (session != null) {
      Analytics.track('read_duration', {
        'article_id': widget.article.id,
        'active_ms': session.activeMs,
        'max_progress': session.maxProgress,
      });
      // Survives the widget: the write completes, then "continue reading"
      // refreshes with the final position.
      session.flush().whenComplete(_progressRevision.bump);
    }
    _scroll.dispose();
    _progress.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Stack(
        children: [
          Listener(
            onPointerDown: (_) => _session?.onInteraction(),
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                key: _contentKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: _headerHeight + topInset,
                    child: CoverHero(
                      article: article,
                      surface: widget.surface,
                      borderRadius: CoverHero.headerRadius,
                    ),
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
                      child: FutureBuilder(
                        future: _loaded,
                        builder: (context, snap) {
                          final paragraphs =
                              snap.data?.paragraphs ?? const <String>[];
                          if (_paragraphKeys.length != paragraphs.length) {
                            _paragraphKeys = [
                              for (final _ in paragraphs) GlobalKey(),
                            ];
                          }
                          return _Body(
                            article: article,
                            paragraphs: paragraphs,
                            paragraphKeys: _paragraphKeys,
                            finished:
                                _finished ||
                                snap.data?.saved?.status ==
                                    ReadingStatus.finished,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Status-bar scrim: clear over the cover, fades in once text would
          // scroll under the system icons.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topInset,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _scroll,
                builder: (context, _) {
                  final offset = _scroll.hasClients ? _scroll.offset : 0.0;
                  final t = ((offset - _headerHeight + 40) / 40).clamp(
                    0.0,
                    1.0,
                  );
                  return ColoredBox(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: t),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: topInset,
            left: 0,
            right: 0,
            child: ReadingProgressBar(progress: _progress),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const BackButtonIcon(),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: SafeArea(
              child: Center(
                child: _RestoreHint(
                  visible: _restoreHint,
                  progress: _progress,
                  onBackToTop: _backToTop,
                ),
              ),
            ),
          ),
          if (_celebrating)
            Positioned.fill(
              child: CelebrationBurst(
                label: '读完啦',
                onDone: () => setState(() => _celebrating = false),
              ),
            ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.article,
    required this.paragraphs,
    required this.paragraphKeys,
    required this.finished,
  });

  final ArticleSummary article;
  final List<String> paragraphs;
  final List<GlobalKey> paragraphKeys;

  /// Shows the "done" illustration after the last paragraph.
  final bool finished;

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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, p) in paragraphs.indexed)
                Padding(
                  key: paragraphKeys[i],
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    p,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                  ),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: finished
              ? const Padding(
                  key: Key('reader-finished'),
                  padding: EdgeInsets.only(top: 24),
                  child: StateIllustration(
                    asset: StateIllustration.readingComplete,
                    title: '已读完这篇',
                    message: '会计入你的阅读统计',
                    width: 160,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        // Room so the last lines can scroll clear of the restore hint.
        const SizedBox(height: 96),
      ],
    );
  }
}

/// "Back where you left off" pill shown after restoring a position.
class _RestoreHint extends StatelessWidget {
  const _RestoreHint({
    required this.visible,
    required this.progress,
    required this.onBackToTop,
  });

  final bool visible;
  final ValueListenable<double> progress;
  final VoidCallback onBackToTop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.6),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Material(
            color: scheme.inverseSurface,
            shape: const StadiumBorder(),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder(
                    valueListenable: progress,
                    builder: (context, v, _) => Text(
                      '已回到上次位置 · ${(v * 100).round()}%',
                      style: TextStyle(color: scheme.onInverseSurface),
                    ),
                  ),
                  TextButton(
                    onPressed: onBackToTop,
                    child: Text(
                      '回到开头',
                      style: TextStyle(color: scheme.inversePrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
