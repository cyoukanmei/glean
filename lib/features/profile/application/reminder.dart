import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import 'reminder_scheduler.dart';

/// Reminder settings as stored.
@immutable
class ReminderState {
  const ReminderState({
    this.enabled = false,
    this.minutes = 20 * 60 + 30,
    this.exact = true,
  });

  final bool enabled;

  /// Scheduled as an exact alarm. False without Android's "闹钟和提醒"
  /// permission: the system may then deliver it up to an hour late.
  final bool exact;

  /// Minutes after midnight, local time.
  final int minutes;

  TimeOfDay get time => TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  String get label =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

enum ReminderAccuracy { exact, inexact }

/// Schedules the system notification; swapped out in tests.
abstract class ReminderScheduler {
  /// Whether alarms may fire on the minute (Android 12+ "闹钟和提醒").
  Future<bool> canBeExact();

  /// Schedules the daily reminder at [time]. [ask] may show the
  /// notification permission prompt; [askExact] opens the system page for
  /// exact alarms when they are not allowed. Null when notifications are
  /// not allowed.
  Future<ReminderAccuracy?> schedule(
    TimeOfDay time, {
    bool ask = true,
    bool askExact = false,
  });
  Future<void> cancel();
}

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => createReminderScheduler(),
);

class ReminderNotifier extends Notifier<ReminderState> {
  static const _enabled = 'reminder.enabled';
  static const _minutes = 'reminder.minutes';
  static const _exact = 'reminder.exact';

  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  ReminderState build() {
    final prefs = ref.watch(prefsProvider);
    return ReminderState(
      enabled: prefs.getBool(_enabled) ?? false,
      minutes: prefs.getInt(_minutes) ?? 20 * 60 + 30,
      exact: prefs.getBool(_exact) ?? true,
    );
  }

  Future<bool> canBeExact() => ref.read(reminderSchedulerProvider).canBeExact();

  /// Turns the reminder on at [time]; [askExact] first opens the system page
  /// for exact alarms if needed. Returns false when the system refused
  /// notifications (the switch stays off).
  Future<bool> enable(TimeOfDay time, {bool askExact = false}) async {
    final result = await ref
        .read(reminderSchedulerProvider)
        .schedule(time, askExact: askExact);
    final ok = result != null;
    final exact = result != ReminderAccuracy.inexact;
    final minutes = time.hour * 60 + time.minute;
    await _prefs.setInt(_minutes, minutes);
    await _prefs.setBool(_enabled, ok);
    await _prefs.setBool(_exact, exact);
    state = ReminderState(enabled: ok, minutes: minutes, exact: exact);
    Analytics.track('reminder_set', {
      'enabled': ok,
      'time': state.label,
      if (ok) 'exact': exact,
    });
    return ok;
  }

  /// Schedules an enabled reminder again, without prompts: at launch and on
  /// returning to the app, so a reminder cleared by a force-stop or an
  /// update comes back, and one becomes exact as soon as the permission is
  /// granted in settings.
  Future<void> restore() async {
    if (!state.enabled) return;
    final result = await ref
        .read(reminderSchedulerProvider)
        .schedule(state.time, ask: false);
    if (result == null || !ref.mounted) return;
    final exact = result == ReminderAccuracy.exact;
    if (exact == state.exact) return;
    await _prefs.setBool(_exact, exact);
    state = ReminderState(enabled: true, minutes: state.minutes, exact: exact);
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
