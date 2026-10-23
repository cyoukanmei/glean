import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/glean_theme.dart';
import '../../../core/design/ios_widgets.dart';
import '../../../core/widgets/state_illustration.dart';
import '../../articles/data/article_repository.dart';
import '../../articles/ui/cover_hero.dart';
import '../../articles/ui/labels.dart';
import '../../vocab/application/word_picking.dart';
import '../../vocab/data/vocab_repository.dart';
import '../../vocab/ui/word_sheet.dart';
import '../application/reader_settings.dart';
import '../application/reading_session.dart';
import '../data/progress_repository.dart';
import 'finish_card.dart';
import 'open_reader.dart';
import 'reader_chrome.dart';
import 'reader_paragraph.dart';
import 'reader_settings_sheet.dart';
import 'reading_progress_bar.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({
    super.key,
    required this.article,
    required this.surface,
    this.jumpTo,
  });

  /// Already loaded by the list, so the header (and the cover Hero's
  /// destination) is built on the very first frame.
  final ArticleSummary article;

  /// List the article was opened from; must match its card's Hero tag.
  final String surface;

  /// Opened from the word list: scroll to where the word was saved and flash
  /// it, instead of restoring the last reading position.
  final WordSource? jumpTo;

  /// Jump-back flash: two amber pulses over the word.
  static const pulseDuration = Duration(milliseconds: 1200);

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
  static const _coverHeight = 300.0;

  /// Positions store the text layout scale, so one saved at another font
  /// size or line spacing restores by paragraph anchor instead of pixels.
  double get _layoutScale => ref.read(readerSettingsProvider).layoutScale;

  late final String _userId = ref.read(currentUserIdProvider);
  late final Future<_Loaded> _loaded = _load();

  /// Read in initState: dispose() must not touch `ref`.
  late final Revision _progressRevision;

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
  bool _finished = false;

  /// Set while the finish card is showing.
  FinishStats? _finishStats;

  /// Neighbouring articles in feed order, for the bottom bar.
  ArticleSummary? _previous;
  ArticleSummary? _next;

  /// Words saved from this article, for the byline.
  int _savedHere = 0;

  /// Lower-cased forms of every saved word, underlined in the text.
  Set<String> _collected = const {};

  /// Word whose definition sheet is open.
  (int paragraph, TextRange range)? _selection;

  /// Word being flashed after a jump from the word list.
  (int paragraph, TextRange range)? _pulseAt;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: ReaderPage.pulseDuration,
  );
  late final Animation<double> _pulseOpacity = _pulse.drive(
    TweenSequence([
      for (final (from, to) in const [
        (0.0, 1.0),
        (1.0, 0.0),
        (0.0, 1.0),
        (1.0, 0.0),
      ])
        TweenSequenceItem(
          tween: Tween(
            begin: from,
            end: to,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 1,
        ),
    ]),
  );

  @override
  void initState() {
    super.initState();
    _progressRevision = ref.read(progressRevisionProvider.notifier);
    _scroll.addListener(_onScroll);
    _lifecycle = AppLifecycleListener(
      onResume: () => _setForeground(true),
      onInactive: () => _setForeground(false),
    );
    _loadCollected();
    _loadNeighbors();
    _start();
  }

  Future<void> _loadCollected() async {
    final vocab = ref.read(vocabRepositoryProvider);
    final (forms, here) = await (
      vocab.collectedForms(_userId),
      vocab.countFromArticle(_userId, widget.article.id),
    ).wait;
    if (mounted) {
      setState(() {
        _collected = forms;
        _savedHere = here;
      });
    }
  }

  Future<void> _loadNeighbors() async {
    final repo = ref.read(articleRepositoryProvider);
    try {
      final (previous, next) = await (
        repo.neighbor(widget.article, newer: true),
        repo.neighbor(widget.article, newer: false),
      ).wait;
      if (!mounted) return;
      setState(() {
        _previous = previous;
        _next = next;
      });
    } catch (e) {
      debugPrint('[reader] neighbours unavailable: $e');
    }
  }

  void _openNeighbor(ArticleSummary article, String surface) =>
      openReader(context, article, surface, replace: true);

  /// Font size or spacing changed: keep the paragraph at the top of the
  /// screen where it was, instead of letting the reflow move the text.
  void _onSettingsChanged(ReaderSettings? before, ReaderSettings after) {
    if (before == null || before.layoutScale == after.layoutScale) return;
    final anchor = _currentPosition();
    if (anchor == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final boxes = _paragraphBoxes();
      if (!mounted || !_scroll.hasClients) return;
      if (anchor.anchorPara >= boxes.length) return;
      final (top, height) = boxes[anchor.anchorPara];
      _scroll.jumpTo(
        (top + anchor.anchorDelta * height).clamp(
          0.0,
          _scroll.position.maxScrollExtent,
        ),
      );
      _onScroll();
    });
  }

  void _share() {
    Clipboard.setData(
      ClipboardData(text: '《${widget.article.title}》· 来自拾读 Glean'),
    );
    Analytics.track('article_share', {'article_id': widget.article.id});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已复制标题，可粘贴分享给朋友')));
  }

  /// Long-press: mark the word, look it up, show the sheet, unmark.
  Future<void> _lookup(String text, int paragraph, TextRange range) async {
    final word = text.substring(range.start, range.end);
    _session?.onInteraction();
    HapticFeedback.selectionClick();
    setState(() => _selection = (paragraph, range));
    final entry = await ref.read(dictionaryRepositoryProvider).lookup(word);
    Analytics.track('word_lookup', {
      'word': word.toLowerCase(),
      'found': entry != null,
      'article_id': widget.article.id,
    });
    if (!mounted) return;
    await WordSheet.show(
      context,
      word: word,
      entry: entry,
      articleTitle: widget.article.title,
      source: WordSource(
        articleId: widget.article.id,
        paraIndex: paragraph,
        charStart: range.start,
        charEnd: range.end,
        sentence: sentenceAround(text, range),
      ),
    );
    if (mounted) setState(() => _selection = null);
  }

  /// Opened from the word list: bring the saved word's paragraph to the
  /// upper part of the screen, then flash the word.
  Future<void> _jump(WordSource source) async {
    final boxes = _paragraphBoxes();
    if (!_scroll.hasClients || source.paraIndex >= boxes.length) return;
    final p = _scroll.position;
    final (top, _) = boxes[source.paraIndex];
    final target = (top - p.viewportDimension * 0.25).clamp(
      0.0,
      p.maxScrollExtent,
    );
    await _scroll.animateTo(
      target,
      duration: ReaderPage.restoreGlide,
      curve: Curves.easeInOutCubic,
    );
    if (!mounted) return;
    setState(
      () => _pulseAt = (
        source.paraIndex,
        TextRange(start: source.charStart, end: source.charEnd),
      ),
    );
    await _pulse.forward(from: 0);
    if (mounted) setState(() => _pulseAt = null);
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
    if (widget.jumpTo case final source?) {
      await _jump(source);
    } else if (loaded.saved != null) {
      await _restore(loaded.saved!);
    }
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
      fontScale: _layoutScale,
      progress: progress.toDouble(),
    );
  }

  Future<void> _restore(ReadingProgress saved) async {
    if (!_scroll.hasClients) return;
    final pos = saved.position;
    var target = pos.scrollOffset;
    if ((pos.fontScale - _layoutScale).abs() > 0.001) {
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

  Future<void> _celebrate() async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Analytics.track('article_finish', {'article_id': widget.article.id});
    setState(() => _finished = true);
    final (saved, total) = await (
      ref
          .read(vocabRepositoryProvider)
          .countFromArticle(_userId, widget.article.id),
      ref.read(progressRepositoryProvider).finishedCount(_userId),
    ).wait;
    if (!mounted) return;
    setState(() {
      _finishStats = FinishStats(
        activeMs: _session?.activeMs ?? 0,
        savedWords: saved,
        finishedTotal: total,
        next: _next,
      );
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
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(vocabRevisionProvider, (_, _) => _loadCollected());
    ref.listen(readerSettingsProvider, _onSettingsChanged);
    final settings = ref.watch(readerSettingsProvider);
    final theme = settings.effectiveTheme(
      systemDark: MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: theme.isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: TweenAnimationBuilder<ReaderPalette>(
        tween: ReaderPaletteTween(end: ReaderPalette.of(theme)),
        duration: const Duration(milliseconds: 200),
        builder: (context, palette, _) => _page(context, settings, palette),
      ),
    );
  }

  Widget _page(
    BuildContext context,
    ReaderSettings settings,
    ReaderPalette palette,
  ) {
    final article = widget.article;
    final padding = MediaQuery.paddingOf(context);
    final headerHeight = _coverHeight + padding.top;
    final previous = _previous;
    final next = _next;
    final finishStats = _finishStats;
    return Scaffold(
      backgroundColor: palette.background,
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
                    height: headerHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CoverHero(
                          article: article,
                          surface: widget.surface,
                          borderRadius: CoverHero.headerRadius,
                        ),
                        // The illustration dissolves into the page colour.
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.55, 1],
                              colors: [
                                palette.background.withValues(alpha: 0),
                                palette.background,
                              ],
                            ),
                          ),
                        ),
                      ],
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
                          final pulseAt = _pulseAt;
                          return _Body(
                            article: article,
                            palette: palette,
                            settings: settings,
                            savedHere: _savedHere,
                            paragraphs: paragraphs,
                            paragraphKeys: _paragraphKeys,
                            finished:
                                _finished ||
                                snap.data?.saved?.status ==
                                    ReadingStatus.finished,
                            collected: _collected,
                            selection: _selection,
                            pulse: pulseAt == null
                                ? null
                                : (pulseAt.$1, pulseAt.$2, _pulseOpacity),
                            onWord: (i, range) =>
                                _lookup(paragraphs[i], i, range),
                            bottomInset: padding.bottom,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Status-bar glass: clear over the cover, frosts in once text would
          // scroll under the system icons.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: padding.top,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _scroll,
                builder: (context, _) {
                  final offset = _scroll.hasClients ? _scroll.offset : 0.0;
                  final t = ((offset - _coverHeight + 40) / 40).clamp(0.0, 1.0);
                  return t == 0
                      ? const SizedBox.shrink()
                      : Opacity(
                          opacity: t,
                          child: Glass(
                            color: palette.background.withValues(alpha: 0.82),
                            child: const SizedBox.expand(),
                          ),
                        );
                },
              ),
            ),
          ),
          Positioned(
            top: padding.top,
            left: 0,
            right: 0,
            child: ReadingProgressBar(
              progress: _progress,
              color: palette.accent,
            ),
          ),
          Positioned(
            top: padding.top + 10,
            left: 16,
            right: 16,
            child: Row(
              children: [
                GlassCircleButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  label: '返回',
                  palette: palette,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                GlassCircleButton(
                  key: const Key('reader-settings'),
                  icon: Icons.text_fields_rounded,
                  label: '阅读设置',
                  palette: palette,
                  onTap: () => ReaderSettingsSheet.show(context),
                ),
                const SizedBox(width: 10),
                GlassCircleButton(
                  icon: Icons.ios_share_rounded,
                  label: '分享',
                  palette: palette,
                  onTap: _share,
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: padding.bottom + 12 + ReaderBottomBar.height + 12,
            child: Center(
              child: _RestoreHint(
                visible: _restoreHint,
                progress: _progress,
                onBackToTop: _backToTop,
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: padding.bottom + 12,
            child: ReaderBottomBar(
              progress: _progress,
              palette: palette,
              onPrevious: previous == null
                  ? null
                  : () => _openNeighbor(previous, 'previous'),
              onNext: next == null ? null : () => _openNeighbor(next, 'next'),
            ),
          ),
          if (finishStats != null)
            Positioned.fill(
              child: FinishOverlay(
                stats: finishStats,
                onNext: (a) => _openNeighbor(a, FinishOverlay.nextSurface),
                onClose: () => setState(() => _finishStats = null),
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
    required this.palette,
    required this.settings,
    required this.savedHere,
    required this.paragraphs,
    required this.paragraphKeys,
    required this.finished,
    required this.collected,
    required this.selection,
    required this.pulse,
    required this.onWord,
    required this.bottomInset,
  });

  final ArticleSummary article;
  final ReaderPalette palette;
  final ReaderSettings settings;
  final int savedHere;
  final List<String> paragraphs;
  final List<GlobalKey> paragraphKeys;

  /// Shows the "done" illustration after the last paragraph.
  final bool finished;

  final Set<String> collected;
  final (int, TextRange)? selection;
  final (int, TextRange, Animation<double>)? pulse;
  final void Function(int paragraph, TextRange range) onWord;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final byline = [
      '${article.wordCount} 词',
      '约 ${readingMinutes(article.wordCount)} 分钟',
      if (savedHere > 0) '已收藏 $savedHere 词',
    ];
    final bodyStyle = TextStyle(
      fontFamily: serifFamily,
      fontFamilyFallback: serifFallback,
      fontSize: settings.fontSize,
      height: settings.spacing.height,
      color: palette.text,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.chipBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                '${categoryLabels[article.category] ?? article.category} · '
                '${levelLabels[article.level] ?? 'L${article.level}'}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: palette.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            article.title,
            style: TextStyle(
              fontFamily: serifFamily,
              fontFamilyFallback: serifFallback,
              fontSize: 30,
              height: 1.18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: palette.title,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            byline.join('  ·  '),
            style: TextStyle(fontSize: 13, color: palette.secondary),
          ),
          const SizedBox(height: 8),
          for (final (i, p) in paragraphs.indexed)
            Padding(
              key: paragraphKeys[i],
              padding: const EdgeInsets.only(top: 16),
              child: ReaderParagraph(
                text: p,
                style: bodyStyle,
                accent: palette.accent,
                collected: collected,
                selected: selection?.$1 == i ? selection!.$2 : null,
                pulse: pulse?.$1 == i ? (pulse!.$2, pulse!.$3) : null,
                onWord: (range) => onWord(i, range),
              ),
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: finished
                ? const Padding(
                    key: Key('reader-finished'),
                    padding: EdgeInsets.only(top: 32),
                    child: Center(
                      child: StateIllustration(
                        asset: StateIllustration.readingComplete,
                        title: '已读完这篇',
                        message: '会计入你的阅读统计',
                        width: 160,
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          // Room so the last lines can scroll clear of the bottom bar.
          SizedBox(height: 120 + bottomInset),
        ],
      ),
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
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.6),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          key: const Key('restore-hint'),
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.only(left: 16, right: 4),
            decoration: BoxDecoration(
              color: const Color(0xE61C1C1E),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 16),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder(
                  valueListenable: progress,
                  builder: (context, v, _) => Text(
                    '已回到上次位置 · ${(v * 100).round()}%',
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ),
                TextButton(
                  onPressed: onBackToTop,
                  child: const Text(
                    '回到开头',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: GleanColors.mintLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
