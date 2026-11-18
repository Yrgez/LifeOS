import 'dart:io' show Platform;

import 'package:local_reminders/local_reminders.dart';

import '../core/reminders.dart';
import 'reminder_scheduler.dart';

/// Напоминания на Android (локальный плагин `packages/local_reminders`).
class LocalReminderScheduler implements ReminderScheduler {
  const LocalReminderScheduler();

  static ReminderScheduler forPlatform() => Platform.isAndroid ? const LocalReminderScheduler() : const UnsupportedReminderScheduler();

  @override
  bool get supported => true;

  @override
  Future<bool> permitted() => LocalReminders.permitted();

  @override
  Future<bool> requestPermission() => LocalReminders.requestPermission();

  @override
  Future<void> replaceAll(List<ReminderPlan> plans) => LocalReminders.replaceAll([
        for (var i = 0; i < plans.length; i++) ScheduledReminder(id: 7000 + i, at: plans[i].at, title: plans[i].title, body: plans[i].body),
      ]);
}
