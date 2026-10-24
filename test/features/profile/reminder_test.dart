import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/app/providers.dart';
import 'package:glean/features/profile/application/reminder.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Scheduler implements ReminderScheduler {
  bool allowed = true;

  /// Whether exact alarms are allowed; [askExact] grants them (the user
  /// allowed it on the system page).
  bool exactAllowed = false;
  TimeOfDay? scheduled;
  int cancels = 0;
  int prompts = 0;

  @override
  Future<bool> canBeExact() async => exactAllowed;

  @override
  Future<ReminderAccuracy?> schedule(
    TimeOfDay time, {
    bool ask = true,
    bool askExact = false,
  }) async {
    if (ask) prompts++;
    if (!allowed) return null;
    if (askExact) exactAllowed = true;
    scheduled = time;
    return exactAllowed ? ReminderAccuracy.exact : ReminderAccuracy.inexact;
  }

  @override
  Future<void> cancel() async => cancels++;
}

Future<(ProviderContainer, _Scheduler)> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final scheduler = _Scheduler();
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      reminderSchedulerProvider.overrideWithValue(scheduler),
    ],
  );
  addTearDown(c.dispose);
  return (c, scheduler);
}

void main() {
  test('off by default at 20:30', () async {
    final (c, _) = await _container();
    final r = c.read(reminderProvider);
    expect(r.enabled, isFalse);
    expect(r.label, '20:30');
  });

  test(
    'enabling schedules it and survives a restart; disabling cancels',
    () async {
      final (c, scheduler) = await _container();
      final ok = await c
          .read(reminderProvider.notifier)
          .enable(const TimeOfDay(hour: 7, minute: 5));
      expect(ok, isTrue);
      expect(scheduler.scheduled, const TimeOfDay(hour: 7, minute: 5));

      final again = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          reminderSchedulerProvider.overrideWithValue(scheduler),
        ],
      );
      addTearDown(again.dispose);
      expect(again.read(reminderProvider).enabled, isTrue);
      expect(again.read(reminderProvider).label, '07:05');

      await c.read(reminderProvider.notifier).disable();
      expect(scheduler.cancels, 1);
      expect(c.read(reminderProvider).enabled, isFalse);
    },
  );

  test('a refused notification permission leaves it off', () async {
    final (c, scheduler) = await _container();
    scheduler.allowed = false;
    final ok = await c
        .read(reminderProvider.notifier)
        .enable(const TimeOfDay(hour: 8, minute: 0));
    expect(ok, isFalse);
    expect(c.read(reminderProvider).enabled, isFalse);
  });

  test(
    'without the exact-alarm permission it is marked late; asking '
    'makes it exact, and a restore picks up a permission granted later',
    () async {
      final (c, scheduler) = await _container();
      final notifier = c.read(reminderProvider.notifier);
      await notifier.enable(const TimeOfDay(hour: 21, minute: 30));
      expect(c.read(reminderProvider).exact, isFalse);

      await notifier.enable(
        const TimeOfDay(hour: 21, minute: 30),
        askExact: true,
      );
      expect(c.read(reminderProvider).exact, isTrue);

      // Revoked in settings, granted again: restore follows, without prompts.
      scheduler.exactAllowed = false;
      final prompts = scheduler.prompts;
      await notifier.restore();
      expect(c.read(reminderProvider).exact, isFalse);
      scheduler.exactAllowed = true;
      await notifier.restore();
      expect(c.read(reminderProvider).exact, isTrue);
      expect(scheduler.prompts, prompts, reason: 'no prompt on restore');
    },
  );

  test('restore does nothing while the reminder is off', () async {
    final (c, scheduler) = await _container();
    await c.read(reminderProvider.notifier).restore();
    expect(scheduler.scheduled, isNull);
  });
}
