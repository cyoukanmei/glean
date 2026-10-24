import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../clock.dart';
import 'collector.dart';
import 'event_queue.dart';
import 'event_spec.dart';

/// Result of one [AnalyticsService.flush].
class FlushResult {
  const FlushResult({this.sent = 0, this.failed = 0, this.skipped});

  final int sent;
  final int failed;

  /// Why nothing was attempted (offline, already running), if so.
  final String? skipped;
}

/// Tracking pipeline: `track` writes to the local queue and returns at once;
/// batches go up in the background with retry and backoff.
///
/// * Common params: device_id, user_id, session_id, seq, app_version,
///   platform, network, ts (see [eventSpecs] for business params).
/// * Sessions: a new session starts on cold start and when the app returns
///   after more than [sessionTimeout] in the background.
/// * Upload: every [flushInterval], when [batchTrigger] events are waiting,
///   when the app goes to the background, when the network comes back, and
///   on cold start (after re-queueing a batch a killed process left behind).
class AnalyticsService extends ChangeNotifier {
  /// Prefs key of the random per-install device id (also used by sync).
  static const deviceIdKey = 'analytics.device_id';

  AnalyticsService({
    required this.queue,
    required this.collector,
    required this.deviceId,
    required this.appVersion,
    required this.platform,
    required this.userId,
    required this.isOnline,
    this._clock = systemClock,
    this.flushInterval = const Duration(seconds: 15),
    this.sessionTimeout = const Duration(seconds: 30),
    this.batchSize = 50,
    this.batchTrigger = 20,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final EventQueue queue;
  final MockCollector collector;
  final String deviceId;
  final String appVersion;
  final String platform;
  final String Function() userId;
  final bool Function() isOnline;
  final Clock _clock;
  final Uuid _uuid;
  final Duration flushInterval;
  final Duration sessionTimeout;
  final int batchSize;
  final int batchTrigger;

  late String _sessionId = _uuid.v4();
  int _seq = 0;
  int _foregroundSince = 0;
  int? _backgroundAt;
  int _unflushed = 0;

  /// Queue writes run one after another so `seq` order is insert order.
  Future<void> _writes = Future.value();
  Future<FlushResult>? _flushing;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;

  String get sessionId => _sessionId;

  Future<void> start({required int coldStartMs}) async {
    await queue.recoverStuck();
    await queue.purgeSent();
    _foregroundSince = _clock();
    track('app_open', {'cold_start_ms': coldStartMs});
    track('session_start', {'reason': 'cold_start'});
    _timer = Timer.periodic(flushInterval, (_) => flush());
    _lifecycle = AppLifecycleListener(
      onPause: _onBackground,
      onResume: _onForeground,
    );
    // Cold-start catch-up of whatever an earlier run could not send.
    unawaited(Future<void>.delayed(const Duration(seconds: 3), flush));
  }

  void _onBackground() {
    final now = _clock();
    _backgroundAt = now;
    track('app_background', {'foreground_ms': now - _foregroundSince});
    flush();
  }

  void _onForeground() {
    final now = _clock();
    final away = _backgroundAt == null ? 0 : now - _backgroundAt!;
    _foregroundSince = now;
    _backgroundAt = null;
    if (away > sessionTimeout.inMilliseconds) {
      _sessionId = _uuid.v4();
      _seq = 0;
      track('session_start', {'reason': 'resume', 'away_ms': away});
    }
    flush();
  }

  /// Network came back: send what queued up offline.
  void onConnectivityChanged(bool online) {
    if (online) flush();
  }

  void track(String name, Map<String, Object?> params) {
    if (kDebugMode) {
      final problems = validateEvent(name, params);
      if (problems.isNotEmpty) {
        debugPrint('[analytics] $name: ${problems.join(', ')}');
      }
    }
    final now = _clock();
    final event = QueuedEvent(
      eventId: _uuid.v4(),
      name: name,
      ts: now,
      sessionId: _sessionId,
      seq: ++_seq,
      userId: userId(),
      params: {
        ...params,
        'device_id': deviceId,
        'app_version': appVersion,
        'platform': platform,
        'network': isOnline() ? 'online' : 'offline',
      },
    );
    _writes = _writes.then((_) => queue.add(event)).catchError((Object e) {
      debugPrint('[analytics] enqueue failed: $e');
    });
    _writes.then((_) => notifyListeners());
    if (++_unflushed >= batchTrigger) flush();
  }

  /// Uploads due events in batches until the queue is empty or a batch
  /// fails. Only one flush runs at a time; callers share the running one.
  Future<FlushResult> flush() => _flushing ??= _flush().whenComplete(() {
    _flushing = null;
    notifyListeners();
  });

  Future<FlushResult> _flush() async {
    await _writes;
    if (!isOnline()) return const FlushResult(skipped: 'offline');
    _unflushed = 0;
    var sent = 0;
    while (true) {
      final batchId = _uuid.v4();
      final events = await queue.claim(batchId, limit: batchSize);
      if (events.isEmpty) return FlushResult(sent: sent);
      final started = _clock();
      int? status;
      String? error;
      try {
        final response = await collector.post(
          jsonEncode({
            'batch_id': batchId,
            'events': [for (final e in events) e.toJson()],
          }),
        );
        status = response.status;
        if (status != 200) error = 'HTTP $status';
      } catch (e) {
        error = '$e';
      }
      await queue.logUpload(
        UploadRecord(
          batchId: batchId,
          sentAt: started,
          count: events.length,
          httpStatus: status,
          error: error,
          durationMs: _clock() - started,
        ),
      );
      if (status == 200) {
        await queue.markSent(batchId);
        sent += events.length;
      } else {
        await queue.markFailed(batchId);
        return FlushResult(sent: sent, failed: events.length);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}
