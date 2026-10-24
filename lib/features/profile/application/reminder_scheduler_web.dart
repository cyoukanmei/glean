import 'package:flutter/material.dart';

import 'reminder.dart';

/// Browsers cannot wake a closed tab at a set time; the web build hides the
/// reminder setting and this never schedules anything.
ReminderScheduler createReminderScheduler() => const _NoReminders();

class _NoReminders implements ReminderScheduler {
  const _NoReminders();

  @override
  Future<bool> canBeExact() async => false;

  @override
  Future<ReminderAccuracy?> schedule(
    TimeOfDay time, {
    bool ask = true,
    bool askExact = false,
  }) async => null;

  @override
  Future<void> cancel() async {}
}
