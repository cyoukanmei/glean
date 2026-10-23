import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../../core/clock.dart';
import '../data/progress_repository.dart';
import '../data/reading_time_repository.dart';

/// Bookkeeping for one visit to the reader: where the reader is, how long
/// they actually read, and whether the article now counts as finished.
///
/// Time is injected and the widget drives it ([tick] every few hundred ms),
/// so every rule below is unit-testable without timers.
///
/// Position writes are throttled: saved [saveDebounce] after scrolling
/// stops, at most every [saveInterval] while scrolling continues, and
/// immediately on [flush] (backgrounding, leaving the page). A process kill
/// therefore loses at most about one second of position.
///
/// Reading time only accrues while the page is visible, the app is in the
/// foreground and the reader interacted within [idleLimit] (a screen of text
/// can take a minute to read, so the limit is generous). Time is stored as
/// segments that rewrite their absolute total every [segmentSaveEvery];
/// segments shorter than [minSegment] are dropped as accidental opens and a
/// single segment is capped at [maxSegment].
class ReadingSession {
  ReadingSession({
    required this.userId,
    required this.articleId,
    required this.wordCount,
    required this.sessionId,
    required this._progress,
    required this._time,
    required this._priorActiveMs,
    required bool alreadyFinished,
    this.onFinished,
    this._clock = systemClock,
    String Function()? newId,
  }) : _newId = newId ?? const Uuid().v4,
       _finished = alreadyFinished {
    _lastInteraction = _clock();
    _startSegment();
  }

  static const saveDebounce = Duration(milliseconds: 500);
  static const saveInterval = Duration(seconds: 1);
  static const idleLimit = Duration(seconds: 120);
  static const segmentSaveEvery = Duration(seconds: 5);
  static const minSegment = Duration(seconds: 3);
  static const maxSegment = Duration(minutes: 30);

  /// Progress needed (as a share of the article seen) to count as read.
  static const finishProgress = 0.9;

  /// Fast skim speed: below words / 400 wpm the reader cannot have read it.
  static const skimWordsPerMinute = 400;
  static const finishMinTimeCap = Duration(seconds: 30);

  final String userId;
  final String articleId;
  final int wordCount;
  final String sessionId;

  /// Called once, the first time this article becomes finished.
  final void Function()? onFinished;

  final ProgressRepository _progress;
  final ReadingTimeRepository _time;
  final Clock _clock;
  final String Function() _newId;
  final int _priorActiveMs;

  bool _finished;
  bool _active = true;
  late int _lastInteraction;

  ReadingPosition? _pending;
  int _pendingSince = 0;
  int _lastPositionSave = 0;
  double _maxProgress = 0;

  late String _segmentId;
  late int _segmentStartedAt;
  int _segmentMs = 0;
  int? _lastTick;
  int _lastSegmentSave = 0;

  /// Minimum reading time for this article to count as finished.
  Duration get finishMinTime {
    final skim = Duration(
      milliseconds: (wordCount / skimWordsPerMinute * 60000).round(),
    );
    return skim < finishMinTimeCap ? skim : finishMinTimeCap;
  }

  int get activeMs => _priorActiveMs + _segmentMs;
  double get maxProgress => _maxProgress;
  bool get finished => _finished;

  void _startSegment() {
    _segmentId = _newId();
    _segmentStartedAt = _clock();
    _segmentMs = 0;
    _lastTick = null;
    _lastSegmentSave = 0;
  }

  /// Seeds the furthest point reached before this visit.
  void restoreMaxProgress(double value) =>
      _maxProgress = max(_maxProgress, value);

  void onInteraction() => _lastInteraction = _clock();

  /// Visible + foreground. Coming back starts a new segment.
  Future<void> setActive(bool active) async {
    if (active == _active) return;
    if (!active) {
      await flush();
    } else {
      _lastInteraction = _clock();
      _startSegment();
    }
    _active = active;
  }

  Future<void> onPosition(ReadingPosition position) async {
    final now = _clock();
    onInteraction();
    _pending = position;
    _pendingSince = now;
    _maxProgress = max(_maxProgress, position.progress);
    if (now - _lastPositionSave >= saveInterval.inMilliseconds) {
      await _savePosition();
    }
    await _checkFinished();
  }

  /// Called periodically (every 250 ms by the reader).
  Future<void> tick() async {
    final now = _clock();
    final previous = _lastTick;
    _lastTick = now;
    final reading =
        _active && now - _lastInteraction <= idleLimit.inMilliseconds;
    if (reading && previous != null) {
      _segmentMs = min(_segmentMs + now - previous, maxSegment.inMilliseconds);
    }

    if (_pending != null &&
        now - _pendingSince >= saveDebounce.inMilliseconds) {
      await _savePosition();
    }
    if (now - _lastSegmentSave >= segmentSaveEvery.inMilliseconds) {
      await _saveSegment();
    }
    await _checkFinished();
  }

  /// Writes everything pending right now.
  Future<void> flush() async {
    await _savePosition();
    await _saveSegment();
  }

  Future<void> _savePosition() async {
    final p = _pending;
    if (p == null) return;
    _pending = null;
    _lastPositionSave = _clock();
    await _progress.save(userId, articleId, p);
  }

  Future<void> _saveSegment() async {
    _lastSegmentSave = _clock();
    if (_segmentMs < minSegment.inMilliseconds) return;
    await _time.saveSegment(
      segmentId: _segmentId,
      userId: userId,
      articleId: articleId,
      sessionId: sessionId,
      startedAt: _segmentStartedAt,
      activeMs: _segmentMs,
    );
  }

  Future<void> _checkFinished() async {
    if (_finished) return;
    if (_maxProgress < finishProgress) return;
    if (activeMs < finishMinTime.inMilliseconds) return;
    _finished = true;
    // Position (and the progress row it creates) must exist before marking.
    await flush();
    if (await _progress.markFinished(userId, articleId)) onFinished?.call();
  }
}
