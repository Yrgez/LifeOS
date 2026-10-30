import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/change_set.dart';
import 'package:life_os/data/sqlite_app_repository.dart';
import 'package:life_os/models/models.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Контроль соответствия: любая последовательность действий контроллера, после сохранения и
/// перезагрузки из SQLite, должна давать ровно то же состояние. Это страховка отслеживания изменений (ChangeSet):
/// если какая-то мутация журнала не попала в ChangeSet, база разойдётся с памятью, и тест это покажет.

/// Репозиторий-обёртка: умеет «ронять» запись и запоминает, какие ChangeSet получал.
class _FlakyRepo implements AppRepository {
  final AppRepository inner;
  int failNext = 0;
  final List<ChangeSet?> seen = [];
  _FlakyRepo(this.inner);

  @override
  Future<AppData?> load() => inner.load();

  @override
  Future<void> save(AppData data, {ChangeSet? changes}) async {
    seen.add(changes);
    if (failNext > 0) {
      failNext--;
      throw StateError('сбой записи');
    }
    return inner.save(data, changes: changes);
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late DateTime now;

  SqliteAppRepository sqlite() => SqliteAppRepository(opener: () async => db);

  AppController make(AppRepository repo, {int maxSets = kMaxWorkoutSets, int maxTx = kMaxTransactions, InitialData? initial}) =>
      AppController(
        repo,
        clock: () => now,
        saveDelay: const Duration(days: 1), // автосохранение по таймеру не мешает: сохраняем только явно
        maxWorkoutSets: maxSets,
        maxTransactions: maxTx,
        initialData: initial,
      );

  /// Состояние, как его увидит новый запуск приложения.
  Future<String> reloaded() async {
    final c = make(sqlite());
    await c.load();
    return c.exportBackup();
  }

  Future<int> count(String table) async => (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).first['n'] as int;
  Future<int> totalChanges() async => (await db.rawQuery('SELECT total_changes() AS n')).first['n'] as int;
  void tick() => now = now.add(const Duration(minutes: 1)); // у записей разные метки времени — порядок однозначен

  setUp(() async {
    now = DateTime(2026, 10, 24, 12);
    db = await SqliteAppRepository.openDb(databaseFactoryFfi, inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  test('подходы: запись, удаление, возврат', () async {
    final c = make(sqlite());
    await c.load();
    for (int i = 0; i < 5; i++) {
      tick();
      c.logWorkout(i.isEven ? 'chest' : 'abs', 40.0 + i, 5 + i);
    }
    await c.flush();
    expect(await reloaded(), c.exportBackup());

    final victim = c.sets[2];
    final removed = c.deleteSet(victim.id)!;
    await c.flush();
    expect(await reloaded(), c.exportBackup());
    expect(await count('workout_sets'), 4);

    c.restoreSet(removed);
    tick();
    c.logWorkout('chest', 100, 3, daysAgo: 2);
    await c.flush();
    expect(await reloaded(), c.exportBackup());
    expect(await count('workout_sets'), 6);
  });

  test('операции: добавление, правка, удаление, возврат', () async {
    final c = make(sqlite());
    await c.load();
    for (int i = 0; i < 4; i++) {
      tick();
      c.addTransaction(categoryId: i.isEven ? 'food' : 'salary', amount: 1000 + i, note: 'n$i');
    }
    await c.flush();
    expect(await reloaded(), c.exportBackup());

    final t = c.transactions[1];
    c.updateTransaction(t.id, categoryId: 'fun', amount: 555, at: t.at, note: 'правка', affectsNetWorth: false);
    final removed = c.deleteTransaction(c.transactions[3].id)!;
    await c.flush();
    expect(await reloaded(), c.exportBackup());

    c.restoreTransaction(removed);
    await c.flush();
    expect(await reloaded(), c.exportBackup());
    expect(await count('money_tx'), 4);
  });

  test('повторяющиеся операции, созданные при смене дня, попадают в базу', () async {
    final c = make(sqlite());
    await c.load();
    c.addRecurring(categoryId: 'subs', amount: 500, dayOfMonth: 24);
    await c.flush();
    now = DateTime(2027, 1, 24, 10);
    await c.onResume();
    await c.flush();
    expect(c.transactions.length, 4); // окт, ноя, дек, янв
    expect(await reloaded(), c.exportBackup());
    expect(await count('money_tx'), 4);
  });

  test('вытеснение старых записей по пределу доходит до базы', () async {
    final c = make(sqlite(), maxSets: 5, maxTx: 4);
    await c.load();
    for (int i = 0; i < 8; i++) {
      tick();
      c.logWorkout('chest', 50.0 + i, 5);
    }
    for (int i = 0; i < 7; i++) {
      tick();
      c.addTransaction(categoryId: 'food', amount: 100 + i);
    }
    await c.flush();
    expect(c.sets.length, 5);
    expect(c.transactions.length, 4);
    expect(await count('workout_sets'), 5);
    expect(await count('money_tx'), 4);
    expect(await reloaded(), c.exportBackup());
  });

  test('импорт копии и сброс данных', () async {
    final a = make(MemoryAppRepository());
    await a.load();
    tick();
    a.logWorkout('abs', 20, 15);
    tick();
    a.addTransaction(categoryId: 'salary', amount: 90000);
    final backup = a.exportBackup();

    final c = make(sqlite());
    await c.load();
    tick();
    c.logWorkout('chest', 100, 5);
    tick();
    c.addTransaction(categoryId: 'food', amount: 700);
    await c.flush();

    expect(c.importBackup(backup), isTrue);
    await c.flush();
    expect(await reloaded(), c.exportBackup());
    expect(await count('workout_sets'), 1);
    expect(c.sets.single.muscleId, 'abs');

    c.resetAllData();
    await c.flush();
    expect(await count('workout_sets'), 0);
    expect(await count('money_tx'), 0);
    expect(await reloaded(), c.exportBackup());
  });

  test('сбой записи: следующее сохранение переписывает журналы целиком и восстанавливает состояние', () async {
    final flaky = _FlakyRepo(sqlite());
    final c = make(flaky);
    await c.load();
    tick();
    c.logWorkout('chest', 100, 5);
    await c.flush();

    flaky.failNext = 1;
    tick();
    c.logWorkout('abs', 20, 10);
    await c.flush(); // упадёт, ошибка проглочена и записана в журнал
    tick();
    c.addTransaction(categoryId: 'food', amount: 700);
    await c.flush(); // успешно

    expect(flaky.seen.last!.full, isTrue);
    expect(await reloaded(), c.exportBackup());
    expect(await count('workout_sets'), 2);
    expect(await count('money_tx'), 1);
  });

  test('параллельные flush-и не теряют изменения', () async {
    final c = make(sqlite());
    await c.load();
    tick();
    c.logWorkout('chest', 100, 5);
    final f1 = c.flush();
    tick();
    c.logWorkout('abs', 20, 10);
    tick();
    c.addTransaction(categoryId: 'food', amount: 300);
    final f2 = c.flush();
    tick();
    c.deleteSet(c.sets.first.id);
    final f3 = c.flush();
    await Future.wait([f1, f2, f3]);
    expect(await reloaded(), c.exportBackup());
  });

  test('flush без изменений ничего не пишет в базу', () async {
    final c = make(sqlite());
    await c.load();
    tick();
    c.logWorkout('chest', 100, 5);
    await c.flush();
    final before = await totalChanges();
    await c.flush();
    await c.flush();
    expect(await totalChanges() - before, 0);
  });

  test('точечное сохранение пишет только изменённые строки журнала', () async {
    final c = make(sqlite());
    await c.load();
    for (int i = 0; i < 30; i++) {
      tick();
      c.logWorkout('chest', 40.0 + i, 5);
    }
    await c.flush();
    final before = await totalChanges();
    tick();
    c.logWorkout('abs', 20, 10);
    await c.flush();
    final delta = await totalChanges() - before;
    // одна строка журнала + немного малых данных (мышца, граф); но не 30+ строк журнала
    expect(delta, lessThan(10));
    expect(await count('workout_sets'), 31);
  });

  test('свежая установка: стартовые журналы записываются целиком', () async {
    final c = make(
      sqlite(),
      initial: (n) {
        final d = AppData.defaults(now: n);
        d.workoutSets.add(WorkoutSet(id: 'seed', muscleId: 'chest', at: n, weight: 80, reps: 5));
        d.transactions.add(MoneyTx(id: 'seedtx', at: n, isIncome: true, amount: 5, categoryId: 'salary'));
        return d;
      },
    );
    await c.load();
    await c.flush();
    expect(await count('workout_sets'), 1);
    expect(await count('money_tx'), 1);
    expect(await reloaded(), c.exportBackup());
  });

  test('длинная смешанная последовательность действий', () async {
    final c = make(sqlite(), maxSets: 12, maxTx: 10);
    await c.load();
    for (int round = 0; round < 6; round++) {
      for (int i = 0; i < 4; i++) {
        tick();
        c.logWorkout(['chest', 'abs', 'quads'][i % 3], 30.0 + round * 5 + i, 3 + i);
        tick();
        c.addTransaction(categoryId: ['food', 'salary', 'fun'][i % 3], amount: 100 * (round + 1) + i);
      }
      if (c.sets.isNotEmpty) c.deleteSet(c.sets[c.sets.length ~/ 2].id);
      if (c.transactions.isNotEmpty) c.deleteTransaction(c.transactions.first.id);
      if (round == 2) c.resetAllData();
      if (round == 4) {
        now = now.add(const Duration(days: 40));
        await c.onResume();
      }
      await c.flush();
      expect(await reloaded(), c.exportBackup(), reason: 'раунд $round');
    }
  });
}
