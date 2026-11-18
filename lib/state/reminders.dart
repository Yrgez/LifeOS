import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_log.dart';
import '../core/reminders.dart';
import '../core/sections.dart';
import '../data/reminder_scheduler.dart';
import 'app_controller.dart';

/// Локальные напоминания: отметка дня, сроки счетов, обзор недели. Всё выключено, пока человек не включит.
/// Расписание пересчитывается при входе в приложение и выходе из него — уже сделанное не напоминается.
/// Настройки — устройства (SharedPreferences), не данных: на другом телефоне человек решит заново.
class Reminders extends ChangeNotifier {
  static const _kCheckIn = 'rm_checkin';
  static const _kCheckInTime = 'rm_checkin_time';
  static const _kBills = 'rm_bills';
  static const _kBillsTime = 'rm_bills_time';
  static const _kReview = 'rm_review';
  static const _kReviewTime = 'rm_review_time';

  Reminders({required this.controller, required this.scheduler, SharedPreferences? prefs}) : _store = prefs;

  factory Reminders.disabled(AppController controller) => Reminders(controller: controller, scheduler: const UnsupportedReminderScheduler());

  final AppController controller;
  final ReminderScheduler scheduler;
  SharedPreferences? _store;

  ReminderPrefs _prefs = const ReminderPrefs();
  bool _permitted = false;
  List<ReminderPlan> _scheduled = const [];

  bool get supported => scheduler.supported;
  ReminderPrefs get prefs => _prefs;
  bool get permitted => _permitted;

  /// Что сейчас поставлено (для строки «ближайшее — …»).
  List<ReminderPlan> get scheduled => List.unmodifiable(_scheduled);

  Future<SharedPreferences> get _p async => _store ??= await SharedPreferences.getInstance();

  Future<void> init() async {
    try {
      final p = await _p;
      ReminderTime t(String k, ReminderTime d) => p.getInt(k) == null ? d : ReminderTime.decode(p.getInt(k)!);
      const d = ReminderPrefs();
      _prefs = ReminderPrefs(
        checkIn: p.getBool(_kCheckIn) ?? false,
        checkInTime: t(_kCheckInTime, d.checkInTime),
        bills: p.getBool(_kBills) ?? false,
        billsTime: t(_kBillsTime, d.billsTime),
        review: p.getBool(_kReview) ?? false,
        reviewTime: t(_kReviewTime, d.reviewTime),
      );
      _permitted = supported && await scheduler.permitted();
    } catch (e, st) {
      AppLog.e('Напоминания: не удалось прочитать настройки', e, st);
    }
    notifyListeners();
  }

  /// Новые настройки. Включение хотя бы одного напоминания запрашивает разрешение на уведомления.
  Future<void> update(ReminderPrefs next) async {
    _prefs = next;
    try {
      final p = await _p;
      await p.setBool(_kCheckIn, next.checkIn);
      await p.setInt(_kCheckInTime, next.checkInTime.encoded);
      await p.setBool(_kBills, next.bills);
      await p.setInt(_kBillsTime, next.billsTime.encoded);
      await p.setBool(_kReview, next.review);
      await p.setInt(_kReviewTime, next.reviewTime.encoded);
    } catch (e, st) {
      AppLog.e('Напоминания: не удалось сохранить настройки', e, st);
    }
    if (next.any && supported && !_permitted) _permitted = await scheduler.requestPermission();
    await resync();
  }

  /// Повторный запрос разрешения (после отказа — человек может разрешить в настройках Android).
  Future<bool> requestPermission() async {
    if (!supported) return false;
    _permitted = await scheduler.requestPermission();
    await resync();
    return _permitted;
  }

  /// Пересчёт расписания по текущим данным. Разделы, скрытые человеком, не напоминают о себе.
  Future<void> resync() async {
    if (!supported || !controller.loaded) return;
    try {
      _permitted = await scheduler.permitted();
      final effective = ReminderPrefs(
        checkIn: _prefs.checkIn && controller.isShown(Sections.checkIn),
        checkInTime: _prefs.checkInTime,
        bills: _prefs.bills && controller.isShown(Sections.bills),
        billsTime: _prefs.billsTime,
        review: _prefs.review && controller.isShown(Sections.review),
        reviewTime: _prefs.reviewTime,
      );
      _scheduled = !_permitted || !effective.any
          ? const []
          : planReminders(
              now: controller.now,
              prefs: effective,
              checkedDays: controller.checkInsByDay.keys.toSet(),
              bills: controller.bills,
              reviewDueAt: controller.nextReviewDueAt,
            );
      await scheduler.replaceAll(_scheduled);
    } catch (e, st) {
      AppLog.e('Напоминания: расписание не обновлено', e, st);
    }
    notifyListeners();
  }
}
