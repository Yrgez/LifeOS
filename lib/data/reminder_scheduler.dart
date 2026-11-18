import '../core/reminders.dart';

/// Показ напоминаний устройством. Плагин — только в реализации (`local_reminder_scheduler.dart`).
abstract class ReminderScheduler {
  bool get supported;

  /// Уведомления разрешены системой.
  Future<bool> permitted();

  /// Запрос разрешения (Android 13+); true — разрешено.
  Future<bool> requestPermission();

  /// Заменяет всё расписание.
  Future<void> replaceAll(List<ReminderPlan> plans);
}

/// Платформа без напоминаний (тесты интерфейса, компьютер).
class UnsupportedReminderScheduler implements ReminderScheduler {
  const UnsupportedReminderScheduler();
  @override
  bool get supported => false;
  @override
  Future<bool> permitted() async => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> replaceAll(List<ReminderPlan> plans) async {}
}

/// Для тестов: запоминает последнее расписание.
class MemoryReminderScheduler implements ReminderScheduler {
  bool allowed;
  bool grantOnRequest;
  List<ReminderPlan> scheduled = const [];
  int replaceCalls = 0;
  MemoryReminderScheduler({this.allowed = false, this.grantOnRequest = true});

  @override
  bool get supported => true;
  @override
  Future<bool> permitted() async => allowed;
  @override
  Future<bool> requestPermission() async => allowed = allowed || grantOnRequest;
  @override
  Future<void> replaceAll(List<ReminderPlan> plans) async {
    replaceCalls++;
    scheduled = List.of(plans);
  }
}
