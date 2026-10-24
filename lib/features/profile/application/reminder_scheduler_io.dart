import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/platform/local_notifications.dart';
import 'reminder.dart';

ReminderScheduler createReminderScheduler() => LocalReminderScheduler();

/// Daily repeating local notification: an exact alarm when allowed,
/// otherwise inexact (Android may then hold it for up to an hour).
class LocalReminderScheduler implements ReminderScheduler {
  final _plugin = LocalNotifications.plugin;
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
    await LocalNotifications.ensureInitialized();
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      LocalNotifications.android;

  @override
  Future<bool> canBeExact() async {
    await _init();
    return await _android?.canScheduleExactNotifications() ?? true;
  }

  @override
  Future<ReminderAccuracy?> schedule(
    TimeOfDay time, {
    bool ask = true,
    bool askExact = false,
  }) async {
    await _init();
    final android = _android;
    final allowed = ask
        ? await android?.requestNotificationsPermission() ?? true
        : await android?.areNotificationsEnabled() ?? true;
    if (!allowed) return null;
    var exact = await android?.canScheduleExactNotifications() ?? true;
    if (!exact && askExact) {
      await android?.requestExactAlarmsPermission();
      exact = await android?.canScheduleExactNotifications() ?? false;
    }
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
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return exact ? ReminderAccuracy.exact : ReminderAccuracy.inexact;
  }

  @override
  Future<void> cancel() async {
    await _init();
    await _plugin.cancel(id: _id);
  }
}
