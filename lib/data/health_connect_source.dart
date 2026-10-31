import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
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
    } catch (e, st) {
      AppLog.e('Health Connect: не удалось прочитать активные калории', e, st);
    }

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

    // Шаги — агрегат платформы (корректно объединяет источники) отдельно на каждый день.
    final out = <HealthDay>[];
    for (final d in days) {
      final next = DateTime(d.year, d.month, d.day + 1);
      int? steps;
      try {
        steps = await _health.getTotalStepsInInterval(d, next.isAfter(now) ? now : next);
      } catch (e, st) {
        AppLog.e('Health Connect: не удалось прочитать шаги за ${d.toIso8601String()}', e, st);
      }
      final kcal = kcalByDay[d];
      final protein = proteinByDay[d];
      out.add(HealthDay(d, steps: steps, activeCalories: kcal?.round(), protein: protein?.round()));
    }
    return out;
  }
}
