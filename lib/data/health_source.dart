/// Данные здоровья за один локальный день. null — источник не дал значение (не путать с нулём).
class HealthDay {
  final DateTime day; // только дата
  final int? steps;
  final int? activeCalories;
  final int? protein; // граммы белка за день из записей питания (Samsung Health и др.)
  final int? sleepMinutes; // сон, завершившийся в этот день (день пробуждения), минуты
  final double? weightKg; // последний замер веса за день
  const HealthDay(this.day, {this.steps, this.activeCalories, this.protein, this.sleepMinutes, this.weightKg});
}

/// Интервал запроса итога шагов за день: ПОЛНЫЕ сутки [полночь, следующая полночь), даже для сегодняшнего дня.
///
/// Health Connect при агрегации делит запись, выходящую за границы интервала, пропорционально времени.
/// Samsung Health пишет шаги одной записью на весь день (00:00–24:00), поэтому запрос «с полуночи до сейчас»
/// возвращал долю: в 12:39 — 52,7% суток, 2 196 вместо 4 163. Шагов из будущего не бывает, так что полные
/// сутки ничего лишнего не добавляют.
({DateTime start, DateTime end}) stepsDayInterval(DateTime day) =>
    (start: DateTime(day.year, day.month, day.day), end: DateTime(day.year, day.month, day.day + 1));

/// Граница между приложением и платформенным источником (Health Connect).
/// Весь платформенный код — в одной реализации; остальное приложение и тесты от плагина не зависят.
abstract class HealthDataSource {
  /// Есть ли источник на этой платформе (сегодня — Android с Health Connect).
  bool get isSupported;

  Future<bool> hasPermission();

  /// Показывает системный запрос разрешений. true — выданы.
  Future<bool> requestPermission();

  /// По одному элементу на каждый локальный день от [from] до [to] включительно (даты без времени).
  Future<List<HealthDay>> readDays(DateTime from, DateTime to);
}

/// Управляемый источник для тестов и превью.
class FakeHealthSource implements HealthDataSource {
  @override
  bool isSupported;
  bool permissionGranted;
  bool grantOnRequest;
  Object? readError;
  Map<DateTime, HealthDay> data;
  int readCalls = 0;
  int requestCalls = 0;

  FakeHealthSource({
    this.isSupported = true,
    this.permissionGranted = false,
    this.grantOnRequest = true,
    this.readError,
    Map<DateTime, HealthDay>? data,
  }) : data = data ?? {};

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<bool> requestPermission() async {
    requestCalls++;
    if (grantOnRequest) permissionGranted = true;
    return permissionGranted;
  }

  @override
  Future<List<HealthDay>> readDays(DateTime from, DateTime to) async {
    readCalls++;
    if (readError != null) throw readError!;
    final out = <HealthDay>[];
    for (var d = DateTime(from.year, from.month, from.day); !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
      out.add(data[d] ?? HealthDay(d));
    }
    return out;
  }
}
