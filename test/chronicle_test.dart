import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/chronicle.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/sqlite_app_repository.dart';
import 'package:life_os/models/day_snapshot.dart';
import 'package:life_os/models/life_event.dart';
import 'package:life_os/models/life_process.dart';
import 'package:life_os/models/models.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DateTime now;
  AppController make(AppRepository repo) => AppController(
        repo,
        clock: () => now,
        saveDelay: const Duration(days: 1),
        initialData: (n) => AppData.blank(now: n),
      );

  setUp(() => now = DateTime(2026, 11, 15, 12));

  group('дневной снимок', () {
    test('JSON и проверка', () {
      final s = DaySnapshot(day: '2026-11-15', steps: 8000, netWorth: -500, graphNodes: 4, activitySource: 'health');
      final back = DaySnapshot.tryFromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>)!;
      expect(back.signature, s.signature);
      expect(back.activeCalories, isNull);
      expect(DaySnapshot.tryFromJson({'day': '2026-02-30'}), isNull);
      expect(DaySnapshot.tryFromJson({'day': '15.11.2026'}), isNull);
      expect(DaySnapshot.tryFromJson({'day': '2026-11-15', 'steps': -1}), isNull);
      expect(DaySnapshot.tryFromJson({'day': '2026-11-15', 'steps': 1.5}), isNull);
      expect(DaySnapshot.tryFromJson({'day': '2026-11-15', 'src': 'guess'}), isNull);
    });
  });

  group('контроллер', () {
    test('снимок дня: ноль не записывается как значение, пока не было ненулевого', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      final today = c.snapshotFor(now)!;
      expect(today.steps, isNull);
      expect(today.netWorth, 0);
      c.updateHealth(steps: 5000);
      expect(c.snapshotFor(now)!.steps, 5000);
      expect(c.snapshotFor(now)!.activitySource, 'manual');
      c.updateHealth(steps: 0); // исправление — уже значение
      expect(c.snapshotFor(now)!.steps, 0);
    });

    test('смена дня: прошлый снимок сохраняется, пропущенные дни — без снимков', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      c.updateHealth(steps: 7000, protein: 120);
      c.updateWealth(netWorth: 100000);
      now = DateTime(2026, 11, 18, 9); // три дня спустя
      c.refresh();
      expect(c.snapshotFor(DateTime(2026, 11, 15))!.steps, 7000);
      expect(c.snapshotFor(DateTime(2026, 11, 15))!.netWorth, 100000);
      expect(c.snapshotFor(DateTime(2026, 11, 16)), isNull);
      expect(c.snapshotFor(DateTime(2026, 11, 17)), isNull);
      expect(c.snapshotFor(now)!.steps, isNull); // новый день: шагов ещё нет
      expect(c.snapshotFor(now)!.netWorth, 100000);
      expect(c.stepsWeekHistory, [0, 0, 0, 7000, 0, 0, 0]);
    });

    test('история не ограничена неделей', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      for (var i = 0; i < 30; i++) {
        c.updateHealth(steps: 1000 + i);
        now = now.add(const Duration(days: 1));
        c.refresh();
      }
      expect(c.snapshots.where((s) => s.steps != null), hasLength(30));
      expect(c.snapshotFor(DateTime(2026, 11, 15))!.steps, 1000);
    });
  });

  group('хроника', () {
    test('события, статусы процессов и достижения в одной ленте', () {
      final ev = LifeEvent(
        id: 'e',
        at: DateTime(2026, 11, 10, 18),
        recordedAt: DateTime(2026, 11, 10, 18),
        dimensions: [LifeDimension.mind],
        kind: LifeEventKind.milestone,
        title: 'Сдал экзамен',
      );
      final p = LifeProcess(
        id: 'p',
        title: 'Java',
        dimensions: [LifeDimension.mind],
        createdAt: DateTime(2026, 9, 1),
        statusLog: [
          ProcessStatusChange(at: DateTime(2026, 9, 1), status: ProcessStatus.active),
          ProcessStatusChange(at: DateTime(2026, 11, 12), status: ProcessStatus.completed, note: 'сертификат'),
        ],
      );
      const achievements = [
        AchievementItem(id: 'a', title: 'Подушка', date: 'Октябрь 2026', category: 'Финансы', iconKey: 'savings'),
        AchievementItem(id: 'b', title: 'Старое', date: 'давно', category: '', iconKey: 'star'),
      ];
      final entries = chronicleEntries(currentEvents: [ev], processes: [p], achievements: achievements);
      expect(entries.map((e) => e.title), ['Процесс завершён: «Java»', 'Сдал экзамен', 'Подушка', 'Начат процесс «Java»']);
      expect(entries.first.detail, 'сертификат');
      expect(undatedAchievements(achievements).single.title, 'Старое');

      final months = groupChronicle(entries, snapshots: {'2026-11-11': DaySnapshot(day: '2026-11-11', steps: 9000)});
      expect(months.map((m) => m.month), [DateTime(2026, 11), DateTime(2026, 10), DateTime(2026, 9)]);
      expect(months.first.days.map((d) => d.day), ['2026-11-12', '2026-11-10']); // тихий день скрыт
      expect(months[1].monthOnly.single.title, 'Подушка');

      final withQuiet = groupChronicle(entries, snapshots: {'2026-11-11': DaySnapshot(day: '2026-11-11', steps: 9000)}, includeQuietDays: true);
      expect(withQuiet.first.days.map((d) => d.day), ['2026-11-12', '2026-11-11', '2026-11-10']);
      expect(withQuiet.first.days[1].snapshot!.steps, 9000);
    });

    test('перенос: последний день берётся из счётчиков, а не из массива', () {
      final d = AppData.fromJson({'lastDay': '2026-11-15', 'dailySteps': 0, 'stepsWeekHistory': [5, 9]});
      expect(d.snapshots['2026-11-15'], isNull); // счётчик дня — 0: шагов за день не было введено
      expect(d.snapshots['2026-11-14']!.steps, 5);
    });

    test('месяц из строки', () {
      expect(parseMonthYear('Октябрь 2026'), DateTime(2026, 10));
      expect(parseMonthYear('  май   2025 '), DateTime(2025, 5));
      expect(parseMonthYear('2026'), isNull);
    });
  });

  group('копии и хранилище', () {
    test('экспорт → импорт сохраняет снимки; строгий импорт отвергает битые и повторы', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      c.updateHealth(steps: 4000);
      now = now.add(const Duration(days: 1));
      c.refresh();
      final raw = c.exportBackup();
      final c2 = make(MemoryAppRepository());
      await c2.load();
      expect(c2.importBackup(raw), isTrue);
      expect(c2.exportBackup(), raw);

      final j = jsonDecode(raw) as Map<String, dynamic>;
      final snaps = j['snapshots'] as List;
      expect(() => AppData.fromJson({...j, 'snapshots': [...snaps, snaps.first]}, strict: true), throwsFormatException);
      expect(() => AppData.fromJson({...j, 'snapshots': [{'day': 'вчера'}]}, strict: true), throwsFormatException);
    });

    test('копия схемы 5 с недельными массивами импортируется в снимки', () async {
      final j = AppData.blank(now: now).toJson()
        ..remove('snapshots')
        ..['schemaVersion'] = 5
        ..['lastDay'] = '2026-11-15'
        ..['stepsWeekHistory'] = [1, 2, 3, 4, 5, 6, 7]
        ..['dailySteps'] = 7;
      final c = make(MemoryAppRepository());
      await c.load();
      expect(c.importBackup(jsonEncode(j)), isTrue);
      expect(c.stepsWeekHistory, [1, 2, 3, 4, 5, 6, 7]);
    });

    test('SQLite: снимки пишутся точечно и переживают перезапуск', () async {
      final db = await SqliteAppRepository.openDb(databaseFactoryFfi, inMemoryDatabasePath);
      addTearDown(db.close);
      final c = make(SqliteAppRepository(opener: () async => db));
      await c.load();
      await c.flush();
      Future<int> total() async => (await db.rawQuery('SELECT total_changes() AS n')).first['n'] as int;
      final before = await total();
      c.updateHealth(steps: 3000);
      await c.flush();
      expect(await total() - before, 2); // снимок дня и скаляр шагов (в чистом графе нет узла «Шаги»)
      final c2 = make(SqliteAppRepository(opener: () async => db));
      await c2.load();
      expect(c2.snapshotFor(now)!.steps, 3000);
      expect(c2.exportBackup(), c.exportBackup());
    });

    test('миграция базы v2 → v3: недельные массивы из kv переезжают в снимки, ключи удаляются', () async {
      final dir = await Directory.systemTemp.createTemp('life_os_snap');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/v2.db';
      final v2 = await SqliteAppRepository.openDb(databaseFactoryFfi, path);
      final c1 = make(SqliteAppRepository(opener: () async => v2));
      await c1.load();
      await c1.flush();
      // «откат» к формату v2: без таблицы снимков, недельные массивы в kv
      await v2.execute('DROP TABLE day_snapshots');
      await v2.insert('kv', {'k': 'stepsWeekHistory', 'v': jsonEncode([0, 0, 0, 0, 0, 6000, 7000])});
      await v2.insert('kv', {'k': 'graphEvolutionHistory', 'v': jsonEncode([4, 4, 4, 4, 4, 4, 5])});
      await v2.update('kv', {'v': jsonEncode('2026-11-15')}, where: "k = 'lastDay'");
      await v2.update('kv', {'v': jsonEncode(7000)}, where: "k = 'dailySteps'"); // как было: последняя точка = счётчик дня
      await v2.setVersion(2);
      await v2.close();

      final v3 = await SqliteAppRepository.openDb(databaseFactoryFfi, path);
      addTearDown(v3.close);
      final c = make(SqliteAppRepository(opener: () async => v3));
      await c.load();
      expect(c.snapshotFor(DateTime(2026, 11, 14))!.steps, 6000);
      expect(c.snapshotFor(DateTime(2026, 11, 15))!.steps, 7000);
      expect(c.snapshotFor(DateTime(2026, 11, 13))!.steps, isNull);
      expect((await v3.query('kv', where: "k = 'stepsWeekHistory'")), isEmpty);
      expect((await v3.rawQuery('SELECT COUNT(*) AS n FROM day_snapshots')).first['n'], 7);

      final again = make(SqliteAppRepository(opener: () async => v3));
      await again.load();
      expect(again.exportBackup(), c.exportBackup());
    });
  });
}
