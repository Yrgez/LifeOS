import 'package:flutter/services.dart';

/// Одно напоминание: когда и что показать.
class ScheduledReminder {
  final int id;
  final DateTime at;
  final String title;
  final String body;
  const ScheduledReminder({required this.id, required this.at, required this.title, required this.body});

  Map<String, Object> toMap() => {'id': id, 'at': at.millisecondsSinceEpoch, 'title': title, 'body': body};
}

/// Локальные напоминания на Android: будильники и уведомления без сети.
class LocalReminders {
  static const _ch = MethodChannel('lifeos/local_reminders');

  /// Уведомления разрешены (Android 13+ — разрешение, раньше — системный переключатель приложения).
  static Future<bool> permitted() async => await _ch.invokeMethod<bool>('permitted') ?? false;

  /// Запрос разрешения на уведомления (Android 13+); true — разрешено.
  static Future<bool> requestPermission() async => await _ch.invokeMethod<bool>('requestPermission') ?? false;

  /// Заменяет всё расписание: прежние напоминания отменяются, новые ставятся.
  static Future<void> replaceAll(List<ScheduledReminder> reminders) =>
      _ch.invokeMethod<void>('replaceAll', {'items': [for (final r in reminders) r.toMap()]});
}
