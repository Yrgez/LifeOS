import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/change_set.dart';
import 'package:life_os/data/sqlite_app_repository.dart';
import 'package:life_os/models/models.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Для запуска нужна системная библиотека sqlite3 (Linux: libsqlite3, macOS: есть из коробки, Windows: sqlite3.dll).

class _CountingLegacy implements AppRepository {
  final AppData? data;
  final Object? error;
  int loads = 0;
  _CountingLegacy({this.data, this.error});

  @override
  Future<AppData?> load() async {
    loads++;
    if (error != null) throw error!;
    return data;
  }

  @override
  Future<void> save(AppData d, {ChangeSet? changes}) async {}
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;

  Future<Database> openMem() => SqliteAppRepository.openDb(databaseFactoryFfi, inMemoryDatabasePath);
  SqliteAppRepository repoOn(Database d, {AppRepository? legacy}) => SqliteAppRepository(opener: () async => d, legacy: legacy);
  Future<int> changes() async => (await db.rawQuery('SELECT total_changes() AS n')).first['n'] as int;
  Future<int> count(String table) async => (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).first['n'] as int;
  String sig(AppData d) => jsonEncode(d.toJson());

  AppData rich() {
    final d = AppData.defaults(now: DateTime(2026, 10, 24));
    d.netWorth = 123456;
    d.healthEnabled = true;
    d.lastHealthSyncMs = 1760000000000;
    d.budgets['food'] = 20000;
    d.budgets['fun'] = 5000;
    d.recurring.add(RecurringTx(id: 'r1', categoryId: 'housing', amount: 40000, dayOfMonth: 25, start: DateTime(2026, 10, 24), note: 'аренда', lastMonth: '2026-10'));
    d.workoutSets.addAll([
      WorkoutSet(id: 's1', muscleId: 'chest', at: DateTime(2026, 10, 20, 10), weight: 82.5, reps: 8),
      WorkoutSet(id: 's2', muscleId: 'abs', at: DateTime(2026, 10, 22, 9, 30), weight: 20, reps: 15),
      WorkoutSet(id: 's3', muscleId: 'chest', at: DateTime(2026, 10, 24, 18), weight: 100, reps: 5),
    ]);
    d.transactions.addAll([
      MoneyTx(id: 't1', at: DateTime(2026, 10, 1, 9), isIncome: true, amount: 100000, categoryId: 'salary', note: "аванс, 'тест' \"кавычки\""),
      MoneyTx(id: 't2', at: DateTime(2026, 10, 5, 12), isIncome: false, amount: 1500, categoryId: 'food', affectsNetWorth: false),
      MoneyTx(id: 't3', at: DateTime(2026, 10, 25, 9), isIncome: false, amount: 40000, categoryId: 'housing', recurringId: 'r1'),
    ]);
    return d;
  }

  setUp(() async => db = await openMem());
  tearDown(() => db.close());

  group('основа', () {
    test('пустая база без прежнего хранилища → null (первый запуск)', () async {
      expect(await repoOn(db).load(), isNull);
    });

    test('save → load возвращает те же данные (все таблицы)', () async {
      final d = rich();
      await repoOn(db).save(d);
      final back = (await repoOn(db).load())!;
      expect(sig(back), sig(d));
    });

    test('порядок списков сохраняется', () async {
      final d = rich();
      d.goals = d.goals.reversed.toList();
      d.achievements = d.achievements.reversed.toList();
      d.salaryHistory = d.salaryHistory.reversed.toList();
      await repoOn(db).save(d);
      final back = (await repoOn(db).load())!;
      expect(back.goals.map((g) => g.id), d.goals.map((g) => g.id));
      expect(back.achievements.map((a) => a.id), d.achievements.map((a) => a.id));
      expect(back.salaryHistory.map((s) => s.year), d.salaryHistory.map((s) => s.year));
      expect(back.muscles.keys, d.muscles.keys);
    });

    test('пустые коллекции остаются пустыми (удалённое не «воскресает» значениями по умолчанию)', () async {
      final d = rich();
      d.goals.clear();
      d.graphEdges.clear();
      d.budgets.clear();
      d.achievements.clear();
      d.workoutSets.clear();
      d.transactions.clear();
      await repoOn(db).save(d);
      final back = (await repoOn(db).load())!;
      expect(back.goals, isEmpty);
      expect(back.graphEdges, isEmpty);
      expect(back.budgets, isEmpty);
      expect(back.achievements, isEmpty);
      expect(back.workoutSets, isEmpty);
      expect(back.transactions, isEmpty);
      expect(back.graphNodes, isNotEmpty); // непустое осталось
    });

    test('значения со спецсимволами и null-поля переживают круг', () async {
      final d = rich();
      d.lastHealthSyncMs = null;
      await repoOn(db).save(d);
      final back = (await repoOn(db).load())!;
      expect(back.lastHealthSyncMs, isNull);
      expect(back.transactions.first.note, "аванс, 'тест' \"кавычки\"");
      expect(back.transactions.last.recurringId, 'r1');
      expect(back.transactions[1].affectsNetWorth, isFalse);
    });
  });

  group('инкрементальная запись', () {
    test('повторное сохранение без изменений не пишет ничего', () async {
      await repoOn(db).save(rich());
      final r2 = repoOn(db);
      final loaded = (await r2.load())!;
      final before = await changes();
      await r2.save(loaded, changes: ChangeSet());
      expect(await changes() - before, 0);
    });

    test('изменение одного подхода = одна изменённая строка', () async {
      final repo = repoOn(db);
      final d = rich();
      await repo.save(d);
      final before = await changes();
      final updated = WorkoutSet(id: 's1', muscleId: 'chest', at: d.workoutSets[0].at, weight: 90, reps: 8);
      d.workoutSets[0] = updated;
      await repo.save(d, changes: ChangeSet()..upsertSet(updated));
      expect(await changes() - before, 1);
      final back = (await repoOn(db).load())!;
      expect(back.workoutSets.firstWhere((s) => s.id == 's1').weight, 90);
    });

    test('удаление подхода', () async {
      final repo = repoOn(db);
      final d = rich();
      await repo.save(d);
      final before = await changes();
      d.workoutSets.removeWhere((s) => s.id == 's2');
      await repo.save(d, changes: ChangeSet()..deleteSet('s2'));
      expect(await changes() - before, 1);
      expect(await count('workout_sets'), 2);
    });

    test('добавление и удаление операций', () async {
      final repo = repoOn(db);
      final d = rich();
      await repo.save(d);

      var before = await changes();
      final n1 = MoneyTx(id: 'n1', at: DateTime(2026, 10, 26), isIncome: false, amount: 1, categoryId: 'food');
      final n2 = MoneyTx(id: 'n2', at: DateTime(2026, 10, 27), isIncome: false, amount: 2, categoryId: 'food');
      d.transactions.addAll([n1, n2]);
      await repo.save(d, changes: ChangeSet()..upsertTx(n1)..upsertTx(n2));
      expect(await changes() - before, 2);
      expect(await count('money_tx'), 5);

      before = await changes();
      d.transactions.removeWhere((t) => t.id == 't2');
      await repo.save(d, changes: ChangeSet()..deleteTx('t2'));
      expect(await changes() - before, 1);
      expect(await count('money_tx'), 4);
    });

    test('точечное сохранение применяет ChangeSet как есть и не перечитывает журналы из данных', () async {
      final repo = repoOn(db);
      await repo.save(rich()); // 3 подхода в базе
      final extra = WorkoutSet(id: 'extra', muscleId: 'abs', at: DateTime(2026, 10, 25), weight: 5, reps: 5);
      final d2 = rich()..workoutSets.clear(); // в данных журнала «нет», но изменение — только extra
      await repo.save(d2, changes: ChangeSet()..upsertSet(extra));
      expect(await count('workout_sets'), 4); // старые строки на месте, extra добавлена
    });

    test('full = true переписывает журналы целиком и убирает лишние строки', () async {
      final repo = repoOn(db);
      await repo.save(rich());
      final d2 = rich()..workoutSets.removeRange(1, 3)..transactions.clear();
      await repo.save(d2, changes: ChangeSet(full: true));
      expect(await count('workout_sets'), 1);
      expect(await count('money_tx'), 0);
    });

    test('без ChangeSet сохранение полное (миграция, импорт)', () async {
      final repo = repoOn(db);
      await repo.save(rich());
      final d2 = rich()..workoutSets.removeLast();
      await repo.save(d2);
      expect(await count('workout_sets'), 2);
    });

    test('изменение скаляра и недельной истории', () async {
      final repo = repoOn(db);
      final d = rich();
      await repo.save(d);
      final before = await changes();
      d.netWorth += 1;
      d.stepsWeekHistory[6] = 1234;
      await repo.save(d, changes: ChangeSet());
      expect(await changes() - before, 2);
    });

    test('смена порядка целей обновляет позиции', () async {
      final repo = repoOn(db);
      final d = rich();
      await repo.save(d);
      d.goals = d.goals.reversed.toList();
      await repo.save(d, changes: ChangeSet());
      final back = (await repoOn(db).load())!;
      expect(back.goals.map((g) => g.id), d.goals.map((g) => g.id));
    });

    test('параллельные сохранения выстраиваются в очередь, итог — последнее состояние', () async {
      final repo = repoOn(db);
      final a = rich();
      final b = AppData.fromJson(a.toJson())..netWorth = 999..workoutSets.removeAt(0);
      final f1 = repo.save(a);
      final f2 = repo.save(b);
      await Future.wait([f1, f2]);
      final back = (await repoOn(db).load())!;
      expect(back.netWorth, 999);
      expect(back.workoutSets.length, 2);
    });

    test('большие журналы: круг и точечная правка', () async {
      final d = AppData.defaults(now: DateTime(2026, 10, 24));
      for (int i = 0; i < 20000; i++) {
        d.workoutSets.add(WorkoutSet(id: 'w$i', muscleId: 'chest', at: DateTime(2026, 1, 1).add(Duration(minutes: i)), weight: 50 + (i % 20), reps: 5));
        d.transactions.add(MoneyTx(id: 'x$i', at: DateTime(2026, 1, 1).add(Duration(minutes: i)), isIncome: i % 7 == 0, amount: 100 + i, categoryId: i % 7 == 0 ? 'salary' : 'food'));
      }
      final repo = repoOn(db);
      await repo.save(d);
      expect(await count('workout_sets'), 20000);
      expect(await count('money_tx'), 20000);

      final r2 = repoOn(db);
      final back = (await r2.load())!;
      expect(back.workoutSets.length, 20000);
      expect(back.transactions.last.id, 'x19999');

      final before = await changes();
      final replaced = MoneyTx(id: back.transactions[10].id, at: back.transactions[10].at, isIncome: false, amount: 1, categoryId: 'food');
      back.transactions[10] = replaced;
      await r2.save(back, changes: ChangeSet()..upsertTx(replaced));
      expect(await changes() - before, 1);
    });
  });

  group('миграция и безопасность', () {
    test('первый запуск: данные переезжают из прежнего хранилища, повторно оно не читается', () async {
      final legacy = _CountingLegacy(data: rich());
      final first = (await repoOn(db, legacy: legacy).load())!;
      expect(legacy.loads, 1);
      expect(sig(first), sig(rich()));
      expect(await count('workout_sets'), 3);

      final legacy2 = _CountingLegacy(error: StateError('не должно читаться'));
      final again = (await repoOn(db, legacy: legacy2).load())!;
      expect(legacy2.loads, 0);
      expect(sig(again), sig(rich()));
    });

    test('прежнее хранилище недоступно → исключение, база остаётся неинициализированной', () async {
      final bad = _CountingLegacy(error: StateError('диск'));
      await expectLater(repoOn(db, legacy: bad).load(), throwsA(isA<StateError>()));
      expect(await count('kv'), 0);
      // позже хранилище починилось — миграция проходит
      final good = _CountingLegacy(data: rich());
      expect(await repoOn(db, legacy: good).load(), isNotNull);
    });

    test('прежнее хранилище пусто (чистая установка) → null', () async {
      expect(await repoOn(db, legacy: _CountingLegacy()).load(), isNull);
    });

    test('схема данных новее приложения → SchemaTooNewException, данные не тронуты', () async {
      await repoOn(db).save(rich());
      await db.update('kv', {'v': '${kSchemaVersion + 1}'}, where: "k = 'schemaVersion'");
      await expectLater(repoOn(db).load(), throwsA(isA<SchemaTooNewException>()));
      expect(await count('workout_sets'), 3);
    });

    test('повреждённая запись пропускается, остальное читается', () async {
      final d = rich();
      await repoOn(db).save(d);
      await db.insert('docs', {'coll': 'goals', 'id': 'broken', 'pos': 99, 'body': '{не json'});
      final back = (await repoOn(db).load())!;
      expect(back.goals.length, d.goals.length);
      expect(back.workoutSets.length, 3);
    });

    test('база новее приложения: открытие отклоняется, файл не пересоздаётся', () async {
      final dir = Directory.systemTemp.createTempSync('life_os_db_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/future.db';
      final future = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: kDbVersion + 4));
      await future.execute('CREATE TABLE marker (x INTEGER)');
      await future.close();

      await expectLater(SqliteAppRepository.openDb(databaseFactoryFfi, path), throwsA(anything));

      final check = await databaseFactoryFfi.openDatabase(path);
      expect(await check.getVersion(), kDbVersion + 4);
      expect((await check.query('sqlite_master', where: "name = 'marker'")).length, 1);
      await check.close();
    });
  });

  group('с контроллером', () {
    test('журнал и операции переживают «перезапуск»', () async {
      final clock = DateTime(2026, 10, 24, 12);
      final c1 = AppController(repoOn(db), clock: () => clock, saveDelay: Duration.zero);
      await c1.load();
      c1.logWorkout('chest', 100, 5);
      c1.addTransaction(categoryId: 'food', amount: 700);
      await c1.flush();

      final c2 = AppController(repoOn(db), clock: () => clock, saveDelay: Duration.zero);
      await c2.load();
      expect(c2.sets.single.weight, 100);
      expect(c2.transactions.single.amount, 700);
      expect(c2.muscles['chest']!.lastSets.first, '100кг × 5');
    });

    test('удаление подхода и операции доходит до базы', () async {
      final clock = DateTime(2026, 10, 24, 12);
      final c1 = AppController(repoOn(db), clock: () => clock, saveDelay: Duration.zero);
      await c1.load();
      c1.logWorkout('chest', 100, 5);
      c1.addTransaction(categoryId: 'food', amount: 700);
      await c1.flush();
      c1.deleteSet(c1.sets.single.id);
      c1.deleteTransaction(c1.transactions.single.id);
      await c1.flush();
      expect(await count('workout_sets'), 0);
      expect(await count('money_tx'), 0);
    });

    test('ошибка чтения прежнего хранилища → контроллер в режиме «только чтение», база пуста', () async {
      final c = AppController(repoOn(db, legacy: _CountingLegacy(error: StateError('диск'))), saveDelay: Duration.zero);
      await c.load();
      expect(c.loadFailed, isTrue);
      c.updateWealth(netWorth: 1);
      await c.flush();
      expect(await count('kv'), 0);
    });
  });
}
