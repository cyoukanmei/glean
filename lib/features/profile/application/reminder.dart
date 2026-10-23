import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';

/// Reminder settings as stored.
@immutable
class ReminderState {
  const ReminderState({this.enabled = false, this.minutes = 20 * 60 + 30});

  final bool enabled;

  /// Minutes after midnight, local time.
  final int minutes;

  TimeOfDay get time => TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  String get label =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

/// Schedules the system notification; swapped out in tests.
abstract class ReminderScheduler {
  /// Returns false when notifications are not allowed.
  Future<bool> schedule(TimeOfDay time);
  Future<void> cancel();
}

/// Daily repeating local notification (inexact, so no exact-alarm
/// permission is needed; Android may shift it by a few minutes).
class LocalReminderScheduler implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _id = 1;

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (e) {
      debugPrint('[reminder] timezone: $e');
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
  }

  @override
  Future<bool> schedule(TimeOfDay time) async {
    await _init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final allowed = await android?.requestNotificationsPermission() ?? true;
    if (!allowed) return false;
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: _id,
      title: '该读一会儿英语了',
      body: '花 10 分钟读一篇，保持连续打卡 🔥',
      scheduledDate: at,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reading',
          '每日阅读提醒',
          channelDescription: '每天提醒一次去读一篇英语文章',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return true;
  }

  @override
  Future<void> cancel() async {
    await _init();
    await _plugin.cancel(id: _id);
  }
}

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => LocalReminderScheduler(),
);

class ReminderNotifier extends Notifier<ReminderState> {
  static const _enabled = 'reminder.enabled';
  static const _minutes = 'reminder.minutes';

  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  ReminderState build() {
    final prefs = ref.watch(prefsProvider);
    return ReminderState(
      enabled: prefs.getBool(_enabled) ?? false,
      minutes: prefs.getInt(_minutes) ?? 20 * 60 + 30,
    );
  }

  /// Turns the reminder on at [time]. Returns false when the system refused
  /// notifications (the switch stays off).
  Future<bool> enable(TimeOfDay time) async {
    final ok = await ref.read(reminderSchedulerProvider).schedule(time);
    final minutes = time.hour * 60 + time.minute;
    await _prefs.setInt(_minutes, minutes);
    await _prefs.setBool(_enabled, ok);
    state = ReminderState(enabled: ok, minutes: minutes);
    Analytics.track('reminder_set', {'enabled': ok, 'time': state.label});
    return ok;
  }

  Future<void> disable() async {
    await ref.read(reminderSchedulerProvider).cancel();
    await _prefs.setBool(_enabled, false);
    state = ReminderState(minutes: state.minutes);
    Analytics.track('reminder_set', {'enabled': false});
  }
}

final reminderProvider = NotifierProvider<ReminderNotifier, ReminderState>(
  ReminderNotifier.new,
);
