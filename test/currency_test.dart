import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/currency.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/sqlite_app_repository.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  // валюта форматирования — общее состояние: после каждого теста возвращаем рубли
  tearDown(() => currentCurrency = currencyByCode(kDefaultCurrency)!);

  final now = DateTime(2026, 11, 16, 12);
  AppController make(AppRepository repo) =>
      AppController(repo, clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n));

  test('старые данные без поля — рубли; неизвестная валюта: загрузка терпима, импорт строг', () {
    expect(AppData.fromJson({}).currency, 'RUB');
    expect(AppData.fromJson({'currency': 'XYZ'}).currency, 'RUB');
    final j = AppData.blank(now: now).toJson()..['currency'] = 'XYZ';
    expect(() => AppData.fromJson(j, strict: true), throwsFormatException);
    expect(AppData.fromJson({...j, 'currency': 'USD'}, strict: true).currency, 'USD');
  });

  test('смена валюты меняет только обозначение', () async {
    final c = make(MemoryAppRepository());
    await c.load();
    c.updateWealth(netWorth: 1500);
    expect(fmtCur(c.netWorth), '1 500 ₽');
    expect(c.setCurrency('XYZ'), isFalse);
    expect(c.setCurrency('USD'), isTrue);
    expect(c.netWorth, 1500); // сумма не пересчитана
    expect(fmtCur(c.netWorth), '1 500 \$');
    c.resetAllData();
    expect(c.currency, 'USD'); // настройка переживает сброс данных
  });

  test('валюта переживает перезапуск (SQLite) и попадает в копию', () async {
    final db = await SqliteAppRepository.openDb(databaseFactoryFfi, inMemoryDatabasePath);
    addTearDown(db.close);
    final c = make(SqliteAppRepository(opener: () async => db));
    await c.load();
    c.setCurrency('EUR');
    await c.flush();
    final c2 = make(SqliteAppRepository(opener: () async => db));
    await c2.load();
    expect(c2.currency, 'EUR');
    expect(cur, '€');
    expect(c2.exportBackup(), contains('"currency": "EUR"'));
  });
}
