import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:health/health.dart';

import '../core/app_log.dart';
import 'health_source.dart';

/// Единственное место, которое знает о плагине `health` (pubspec: `health: ^12.0.0`).
/// Читает шаги, активные калории и белок (из записей питания) из Health Connect
/// (Samsung Health, Google Fit, часы и другие приложения пишут туда же).
/// Если API плагина изменится в новой мажорной версии — правится только этот файл.
class HealthConnectSource implements HealthDataSource {
  final Health _health = Health();
  bool _configured = false;

  static const _types = [HealthDataType.STEPS, HealthDataType.ACTIVE_ENERGY_BURNED];
  static const _access = [HealthDataAccess.READ, HealthDataAccess.READ];

  // Питание запрашивается отдельно и необязательно: отказ не ломает шаги и калории.
  static const _nutrition = [HealthDataType.NUTRITION];
  static const _nutritionAccess = [HealthDataAccess.READ];

  // Сон и вес — тоже отдельно и необязательно (нужны READ_SLEEP и READ_WEIGHT в манифесте, см. docs/HEALTH_SETUP.md).
  static const _body = [HealthDataType.SLEEP_SESSION, HealthDataType.WEIGHT];
  static const _bodyAccess = [HealthDataAccess.READ, HealthDataAccess.READ];

  // Только Android: на iOS чтение разрешений скрыто системой, там нужна отдельная логика.
  @override
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<bool> hasPermission() async {
    await _ensureConfigured();
    return await _health.hasPermissions(_types, permissions: _access) ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    await _ensureConfigured();
    final ok = await _health.requestAuthorization(_types, permissions: _access);
    if (ok) {
      // Второй запрос — доступ к питанию (белок). Результат не важен для подключения.
      try {
        await _health.requestAuthorization(_nutrition, permissions: _nutritionAccess);
      } catch (e, st) {
        AppLog.e('Health Connect: не удалось запросить доступ к питанию', e, st);
      }
      try {
        await _health.requestAuthorization(_body, permissions: _bodyAccess);
      } catch (e, st) {
        AppLog.e('Health Connect: не удалось запросить доступ ко сну и весу', e, st);
      }
    }
    return ok;
  }

  @override
  Future<List<HealthDay>> readDays(DateTime from, DateTime to) async {
    await _ensureConfigured();
    final now = DateTime.now();
    final days = <DateTime>[
      for (var d = DateTime(from.year, from.month, from.day); !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) d,
    ];

    // Запросы друг от друга не зависят — идут параллельно, а не по очереди.
    Future<Map<DateTime, double>> readKcal() async {
      // Калории — одним запросом на весь период, затем раскладываем по дням.
      // removeDuplicates: несколько приложений могут писать одни и те же калории.
      final kcalByDay = <DateTime, double>{};
      try {
        var points = await _health.getHealthDataFromTypes(
          types: const [HealthDataType.ACTIVE_ENERGY_BURNED],
          startTime: days.first,
          endTime: now,
        );
        points = _health.removeDuplicates(points);
        for (final p in points) {
          final v = p.value;
          if (v is NumericHealthValue) {
            final key = DateTime(p.dateFrom.year, p.dateFrom.month, p.dateFrom.day);
            kcalByDay[key] = (kcalByDay[key] ?? 0) + v.numericValue.toDouble();
          }
        }
        // Диагностика: видно, отдаёт ли источник активные калории вообще.
        if (points.isEmpty) {
          AppLog.d('Диагностика Health Connect: записей активных калорий нет — источник (например, Samsung Health) '
              'не передаёт их в Health Connect');
        } else {
          final src = points.map((p) => p.sourceName).toSet().join(', ');
          AppLog.d('Диагностика Health Connect: активных калорий — записей ${points.length}, источники: $src');
        }
      } catch (e, st) {
        AppLog.e('Health Connect: не удалось прочитать активные калории', e, st);
      }
      return kcalByDay;
    }

    Future<Map<DateTime, double>> readProtein() async {
      // Белок — сумма по записям питания за день. Читаем только если доступ выдан.
      final proteinByDay = <DateTime, double>{};
      try {
        final granted = await _health.hasPermissions(_nutrition, permissions: _nutritionAccess) ?? false;
        if (granted) {
          var meals = await _health.getHealthDataFromTypes(
            types: const [HealthDataType.NUTRITION],
            startTime: days.first,
            endTime: now,
          );
          meals = _health.removeDuplicates(meals);
          for (final p in meals) {
            final v = p.value;
            if (v is NutritionHealthValue) {
              final g = v.protein;
              if (g != null && g.isFinite) {
                final key = DateTime(p.dateFrom.year, p.dateFrom.month, p.dateFrom.day);
                proteinByDay[key] = (proteinByDay[key] ?? 0) + g;
              }
            }
          }
        }
      } catch (e, st) {
        AppLog.e('Health Connect: не удалось прочитать питание (белок)', e, st);
      }
      return proteinByDay;
    }

    Future<({Map<DateTime, double> sleep, Map<DateTime, ({DateTime at, double kg})> weight})> readBody() async {
      // Сон — сеансы, отнесённые к дню пробуждения; вес — последний замер дня. Читаем, только если доступ выдан.
      final sleepByDay = <DateTime, double>{};
      final weightByDay = <DateTime, ({DateTime at, double kg})>{};
      try {
        final granted = await _health.hasPermissions(_body, permissions: _bodyAccess) ?? false;
        if (granted) {
          var sleeps = await _health.getHealthDataFromTypes(
            types: const [HealthDataType.SLEEP_SESSION],
            startTime: days.first.subtract(const Duration(days: 1)), // ночь накануне первого дня
            endTime: now,
          );
          sleeps = _health.removeDuplicates(sleeps);
          for (final p in sleeps) {
            final v = p.value;
            if (v is NumericHealthValue) {
              final key = DateTime(p.dateTo.year, p.dateTo.month, p.dateTo.day);
              if (!key.isBefore(days.first)) sleepByDay[key] = (sleepByDay[key] ?? 0) + v.numericValue.toDouble();
            }
          }
          var ws = await _health.getHealthDataFromTypes(types: const [HealthDataType.WEIGHT], startTime: days.first, endTime: now);
          ws = _health.removeDuplicates(ws);
          for (final p in ws) {
            final v = p.value;
            if (v is NumericHealthValue) {
              final key = DateTime(p.dateFrom.year, p.dateFrom.month, p.dateFrom.day);
              final prev = weightByDay[key];
              if (prev == null || p.dateFrom.isAfter(prev.at)) weightByDay[key] = (at: p.dateFrom, kg: v.numericValue.toDouble());
            }
          }
          AppLog.d('Health Connect: сон — сеансов ${sleeps.length}, вес — замеров ${ws.length}');
        }
      } catch (e, st) {
        AppLog.e('Health Connect: не удалось прочитать сон и вес', e, st);
      }
      return (sleep: sleepByDay, weight: weightByDay);
    }

    // Шаги — агрегат платформы (корректно объединяет источники) отдельно на каждый день.
    Future<int?> readSteps(DateTime d) async {
      final interval = stepsDayInterval(d); // полные сутки, иначе запись Samsung Health на весь день делится пропорционально
      try {
        return await _health.getTotalStepsInInterval(interval.start, interval.end);
      } catch (e, st) {
        AppLog.e('Health Connect: не удалось прочитать шаги за ${d.toIso8601String()}', e, st);
        return null;
      }
    }

    final kcalF = readKcal(), proteinF = readProtein(), bodyF = readBody();
    final stepsF = Future.wait([for (final d in days) readSteps(d)]);
    final kcalByDay = await kcalF, proteinByDay = await proteinF, body = await bodyF, steps = await stepsF;
    if (kDebugMode) await _logStepsDiagnostics(days.last, now, steps.last);
    return [
      for (final (i, d) in days.indexed)
        HealthDay(d,
            steps: steps[i],
            activeCalories: kcalByDay[d]?.round(),
            protein: proteinByDay[d]?.round(),
            sleepMinutes: body.sleep[d]?.round(),
            weightKg: body.weight[d]?.kg),
    ];
  }

  /// Сверка шагов за сегодня: агрегат платформы против суммы отдельных записей (с источниками).
  /// Только в отладочной сборке: это лишний запрос всех записей шагов за день.
  Future<void> _logStepsDiagnostics(DateTime day, DateTime now, int? aggregate) async {
    try {
      var pts = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.STEPS],
        startTime: day,
        endTime: now,
      );
      pts = _health.removeDuplicates(pts);
      double sum = 0;
      final bySource = <String, double>{};
      for (final p in pts) {
        final v = p.value;
        if (v is NumericHealthValue) {
          sum += v.numericValue.toDouble();
          bySource[p.sourceName] = (bySource[p.sourceName] ?? 0) + v.numericValue.toDouble();
        }
      }
      final src = bySource.entries.map((e) => '${e.key}: ${e.value.round()}').join('; ');
      AppLog.d('Диагностика Health Connect: шаги сегодня — агрегат $aggregate, сумма записей ${sum.round()} '
          '(записей ${pts.length}; $src)');
    } catch (e, st) {
      AppLog.e('Health Connect: диагностика шагов не удалась', e, st);
    }
  }
}
