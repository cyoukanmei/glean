import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/app/providers.dart';
import 'package:glean/features/profile/application/reminder.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Scheduler implements ReminderScheduler {
  bool allowed = true;
  TimeOfDay? scheduled;
  int cancels = 0;

  @override
  Future<bool> schedule(TimeOfDay time) async {
    if (allowed) scheduled = time;
    return allowed;
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
}
