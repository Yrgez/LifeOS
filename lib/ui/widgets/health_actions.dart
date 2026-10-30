import 'package:flutter/material.dart';

import '../../core/utils.dart';
import '../../state/app_controller.dart';
import 'toast.dart';

/// Строка статуса Health Connect (общая для карточки здоровья, настроек и знакомства).
String healthStatusLine(AppController c) {
  if (c.healthMessage != null) return c.healthMessage!;
  if (!c.healthSupported) return 'Ручной ввод (Health Connect доступен на Android)';
  if (!c.healthEnabled) return 'Ручной ввод • нажмите ⟳, чтобы подключить Health Connect';
  final t = c.lastHealthSync;
  return t == null ? 'Health Connect • ожидание синхронизации' : 'Health Connect • синхр. ${fmtTime(t)}';
}

/// Подключает Health Connect (если ещё не подключён) или синхронизирует данные и показывает итог.
Future<void> syncHealthWithToast(BuildContext context, AppController c) async {
  final st = c.healthEnabled ? await c.syncHealth() : await c.connectHealth();
  if (!context.mounted) return;
  showToast(context, switch (st) {
    HealthSyncStatus.ok => 'Данные Health Connect обновлены',
    HealthSyncStatus.unsupported => 'Health Connect недоступен на этом устройстве',
    HealthSyncStatus.permissionDenied => c.healthMessage ?? 'Доступ к Health Connect не выдан',
    HealthSyncStatus.failed => c.healthMessage ?? 'Не удалось синхронизировать',
    HealthSyncStatus.busy => 'Синхронизация уже идёт',
  });
}
