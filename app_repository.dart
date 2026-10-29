import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_log.dart';
import 'app_data.dart';
import 'change_set.dart';

/// Граница между логикой и хранилищем. Сегодня — SharedPreferences,
/// завтра — Drift/Isar/облако: контроллер об этом не знает.
abstract class AppRepository {
  /// null — данных ещё нет (первый запуск). Исключение — хранилище недоступно или данные
  /// от более новой версии приложения; в этом случае контроллер ничего не перезаписывает.
  Future<AppData?> load();
  /// [changes] — что изменилось в журналах с прошлого сохранения. null или `full` — переписать всё.
  /// Реализации, хранящие данные целиком (SharedPreferences, память), параметр игнорируют.
  Future<void> save(AppData data, {ChangeSet? changes});
}

class SchemaTooNewException implements Exception {
  final int version;
  const SchemaTooNewException(this.version);
  @override
  String toString() => 'Данные сохранены более новой версией приложения (схема $version, поддерживается до $kSchemaVersion)';
}

/// Хранит ВСЁ состояние одним JSON-блобом: запись атомарна (раньше — 16 отдельных ключей,
/// которые могли записаться наполовину) и быстрее.
class PrefsAppRepository implements AppRepository {
  static const dataKey = 'life_os_data_v3';
  static const corruptKey = 'life_os_data_v3.corrupt';

  SharedPreferences? _cached;

  Future<SharedPreferences> _prefs() async =>
      _cached ??= await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));

  @override
  Future<AppData?> load() async {
    final p = await _prefs();
    final raw = p.getString(dataKey);

    if (raw != null) {
      try {
        final j = jsonDecode(raw);
        if (j is! Map<String, dynamic>) throw const FormatException('корень JSON не объект');
        final v = (j['schemaVersion'] as num?)?.toInt() ?? 1;
        if (v > kSchemaVersion) throw SchemaTooNewException(v);
        return AppData.fromJson(j);
      } on SchemaTooNewException {
        rethrow;
      } catch (e, st) {
        AppLog.e('Сохранённые данные повреждены, копия отложена в $corruptKey', e, st);
        await p.setString(corruptKey, raw);
      }
    }

    if (hasLegacy(p)) {
      AppLog.e('Найдены данные старого формата (v2), выполняется миграция');
      return AppData.fromJson(legacyToJson(p));
    }
    return null;
  }

  @override
  Future<void> save(AppData data, {ChangeSet? changes}) async {
    final p = await _prefs();
    await p.setString(dataKey, jsonEncode(data.toJson()));
  }

  // ---- миграция со старого формата (отдельные ключи). Старые ключи НЕ удаляются — можно откатиться. ----

  static bool hasLegacy(SharedPreferences p) =>
      p.containsKey('life_os_muscles') || p.containsKey('life_os_net_worth') || p.containsKey('life_os_goals');

  static Map<String, dynamic> legacyToJson(SharedPreferences p) {
    dynamic dec(String k) {
      final r = p.getString(k);
      if (r == null) return null;
      try {
        return jsonDecode(r);
      } catch (e, st) {
        AppLog.e('Миграция: ключ $k не читается', e, st);
        return null;
      }
    }

    return {
      'netWorth': p.getInt('life_os_net_worth'),
      'monthlyIncome': p.getInt('life_os_income'),
      'monthlyExpense': p.getInt('life_os_expense'),
      'dailySteps': p.getInt('life_os_steps'),
      'activeCalories': p.getInt('life_os_cals'),
      'proteinGrams': p.getInt('life_os_prot'),
      'lastDay': p.getString('life_os_day'),
      'muscles': dec('life_os_muscles'),
      'goals': dec('life_os_goals'),
      'achievements': dec('life_os_achievements'),
      'salaryHistory': dec('life_os_salary'),
      'graphNodes': dec('life_os_nodes_v3') ?? dec('life_os_nodes_v2'),
      'graphEdges': dec('life_os_edges_v2'),
      'stepsWeekHistory': dec('life_os_steps_hist'),
      'caloriesWeekHistory': dec('life_os_cals_hist'),
      'graphEvolutionHistory': dec('life_os_graph_hist'),
    };
  }
}

/// Репозиторий в памяти: для тестов и превью.
class MemoryAppRepository implements AppRepository {
  AppData? data;
  Object? loadError;
  int saveCalls = 0;

  MemoryAppRepository({this.data, this.loadError});

  @override
  Future<AppData?> load() async {
    if (loadError != null) throw loadError!;
    return data;
  }

  @override
  Future<void> save(AppData d, {ChangeSet? changes}) async {
    saveCalls++;
    data = AppData.fromJson(d.toJson()); // имитируем сериализацию: ловит ошибки toJson/fromJson
  }
}
