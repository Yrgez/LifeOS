import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/health_source.dart';
import 'package:life_os/state/app_controller.dart';

void main() {
  // 24.10.2026, суббота
  late DateTime now;
  late FakeHealthSource src;
  late MemoryAppRepository repo;

  AppController make({AppData? data, HealthDataSource? health, bool noHealth = false}) {
    repo = MemoryAppRepository(data: data);
    return AppController(repo, clock: () => now, saveDelay: Duration.zero, health: noHealth ? null : (health ?? src));
  }

  Map<DateTime, HealthDay> week() => {
        for (int i = 0; i < 7; i++)
          DateTime(2026, 10, 18 + i): HealthDay(DateTime(2026, 10, 18 + i), steps: 1000 * (i + 1), activeCalories: 100 * (i + 1)),
      };

  setUp(() {
    now = DateTime(2026, 10, 24, 12);
    src = FakeHealthSource(data: week());
  });

  group('подключение', () {
    test('без источника — «не поддерживается», приложение работает вручную', () async {
      final c = make(noHealth: true);
      await c.load();
      expect(c.healthSupported, isFalse);
      expect(await c.connectHealth(), HealthSyncStatus.unsupported);
      expect(await c.syncHealth(), HealthSyncStatus.unsupported);
    });

    test('источник не поддерживается на платформе', () async {
      final c = make(health: FakeHealthSource(isSupported: false));
      await c.load();
      expect(await c.connectHealth(), HealthSyncStatus.unsupported);
      expect(c.healthEnabled, isFalse);
    });

    test('разрешение выдано: включается автосинхронизация и подтягиваются данные', () async {
      final c = make();
      await c.load();
      expect(await c.connectHealth(), HealthSyncStatus.ok);
      expect(src.requestCalls, 1);
      expect(c.healthEnabled, isTrue);
      expect(c.stepsWeekHistory, [1000, 2000, 3000, 4000, 5000, 6000, 7000]);
      expect(c.caloriesWeekHistory, [100, 200, 300, 400, 500, 600, 700]);
      expect(c.dailySteps, 7000);
      expect(c.activeCalories, 700);
      expect(c.lastHealthSync, now);
    });

    test('разрешение не выдано: ничего не включается, есть сообщение', () async {
      src.grantOnRequest = false;
      final c = make();
      await c.load();
      expect(await c.connectHealth(), HealthSyncStatus.permissionDenied);
      expect(c.healthEnabled, isFalse);
      expect(c.healthMessage, isNotNull);
      expect(c.dailySteps, 8420); // ручные данные не тронуты
    });

    test('отключение выключает автосинхронизацию', () async {
      final c = make();
      await c.load();
      await c.connectHealth();
      c.disconnectHealth();
      expect(c.healthEnabled, isFalse);
    });
  });

  group('синхронизация', () {
    test('отозванное разрешение: статус и выключение, данные остаются', () async {
      final c = make();
      await c.load();
      await c.connectHealth();
      src.permissionGranted = false;
      expect(await c.syncHealth(), HealthSyncStatus.permissionDenied);
      expect(c.healthEnabled, isFalse);
      expect(c.dailySteps, 7000);
    });

    test('ошибка чтения: статус failed, данные не портятся', () async {
      final c = make();
      await c.load();
      src.permissionGranted = true;
      src.readError = StateError('Health Connect недоступен');
      expect(await c.syncHealth(), HealthSyncStatus.failed);
      expect(c.healthMessage, isNotNull);
      expect(c.dailySteps, 8420);
      expect(c.healthSyncing, isFalse);
    });

    test('пустые значения источника не затирают существующие', () async {
      src.data = {
        DateTime(2026, 10, 23): HealthDay(DateTime(2026, 10, 23), steps: 4000), // калорий нет
        DateTime(2026, 10, 24): HealthDay(DateTime(2026, 10, 24)), // сегодня — ничего
      };
      final c = make();
      await c.load();
      final calsBefore = c.caloriesWeekHistory.toList();
      await c.connectHealth();
      expect(c.stepsWeekHistory[5], 4000);
      expect(c.caloriesWeekHistory[5], calsBefore[5]); // калории за вчера остались
      expect(c.dailySteps, 8420); // шаги сегодня остались ручными
      expect(c.activeCalories, 540);
    });

    test('параллельный вызов получает busy, флаг синхронизации снимается', () async {
      final c = make();
      await c.load();
      src.permissionGranted = true;
      final f1 = c.syncHealth();
      final f2 = c.syncHealth();
      expect(await f2, HealthSyncStatus.busy);
      expect(await f1, HealthSyncStatus.ok);
      expect(c.healthSyncing, isFalse);
    });

    test('новый день + синхронизация: история выровнена по реальным датам', () async {
      final data = AppData.defaults(now: DateTime(2026, 10, 22))..healthEnabled = true;
      src.permissionGranted = true;
      final c = make(data: data);
      await c.load(); // автосинхронизация запускается сама
      await Future<void>.delayed(Duration.zero);
      expect(c.stepsWeekHistory, [1000, 2000, 3000, 4000, 5000, 6000, 7000]);
      expect(c.dailySteps, 7000);
    });

    test('ручной ввод белка не затирается синхронизацией', () async {
      final c = make();
      await c.load();
      c.updateHealth(protein: 160);
      await c.connectHealth();
      expect(c.proteinGrams, 160);
    });

    test('белок из источника заменяет значение за сегодня', () async {
      src.data = {
        DateTime(2026, 10, 24): HealthDay(DateTime(2026, 10, 24), steps: 5000, protein: 120),
      };
      final c = make();
      await c.load();
      await c.connectHealth();
      expect(c.proteinGrams, 120);
    });

    test('нулевой белок из источника не затирает ручной ввод', () async {
      src.data = {
        DateTime(2026, 10, 24): HealthDay(DateTime(2026, 10, 24), steps: 5000, protein: 0),
      };
      final c = make();
      await c.load();
      c.updateHealth(protein: 160);
      await c.connectHealth();
      expect(c.proteinGrams, 160);
    });
  });

  group('автосинхронизация', () {
    test('выключена — источник не читается', () async {
      src.permissionGranted = true;
      final c = make(data: AppData.defaults(now: now));
      await c.load();
      await Future<void>.delayed(Duration.zero);
      expect(src.readCalls, 0);
    });

    test('включена: синхронизируется при запуске', () async {
      src.permissionGranted = true;
      final c = make(data: AppData.defaults(now: now)..healthEnabled = true);
      await c.load();
      await Future<void>.delayed(Duration.zero);
      expect(src.readCalls, 1);
    });

    test('не чаще раза в 2 минуты', () async {
      src.permissionGranted = true;
      final data = AppData.defaults(now: now)
        ..healthEnabled = true
        ..lastHealthSyncMs = now.subtract(const Duration(seconds: 60)).millisecondsSinceEpoch;
      final c = make(data: data);
      await c.load();
      await Future<void>.delayed(Duration.zero);
      expect(src.readCalls, 0);

      now = now.add(const Duration(minutes: 5));
      await c.onResume();
      await Future<void>.delayed(Duration.zero);
      expect(src.readCalls, 1);
    });
  });

  test('состояние подключения переживает перезапуск', () async {
    final c = make();
    await c.load();
    await c.connectHealth();
    await c.flush();
    final c2 = AppController(repo, clock: () => now, saveDelay: Duration.zero, health: src);
    await c2.load();
    expect(c2.healthEnabled, isTrue);
    expect(c2.lastHealthSync, isNotNull);
  });
}
