/// Данные здоровья за один локальный день. null — источник не дал значение (не путать с нулём).
class HealthDay {
  final DateTime day; // только дата
  final int? steps;
  final int? activeCalories;
  const HealthDay(this.day, {this.steps, this.activeCalories});
}

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
