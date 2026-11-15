import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/sqlite_app_repository.dart';
import 'package:life_os/models/life_event.dart';
import 'package:life_os/models/life_process.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DateTime now;
  void tick([Duration d = const Duration(minutes: 1)]) => now = now.add(d);

  AppController make(AppRepository repo) => AppController(
        repo,
        clock: () => now,
        saveDelay: const Duration(days: 1),
        initialData: (n) => AppData.blank(now: n),
      );

  setUp(() => now = DateTime(2026, 11, 15, 12));

  group('модель', () {
    LifeProcess proc() => LifeProcess(
          id: 'p1',
          title: 'Изучение Java',
          description: 'смена профессии',
          dimensions: [LifeDimension.material, LifeDimension.mind],
          goalIds: ['g1', 'g1'],
          createdAt: DateTime(2026, 9, 2),
          statusLog: [
            ProcessStatusChange(at: DateTime(2026, 9, 1), status: ProcessStatus.active),
            ProcessStatusChange(at: DateTime(2026, 10, 1), status: ProcessStatus.paused, note: 'отпуск'),
          ],
        );

    test('JSON: круг без потерь, производные поля', () {
      final p = proc();
      expect(p.dimensions, [LifeDimension.mind, LifeDimension.material]);
      expect(p.goalIds, ['g1']);
      expect(p.status, ProcessStatus.paused);
      expect(p.isOpen, isTrue);
      expect(p.startedAt, DateTime(2026, 9, 1));
      expect(p.endedAt, isNull);
      final back = LifeProcess.tryFromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>)!;
      expect(jsonEncode(back.toJson()), jsonEncode(p.toJson()));
    });

    test('битые записи отвергаются', () {
      Map<String, dynamic> j(Map<String, dynamic> patch) => {...proc().toJson(), ...patch};
      expect(LifeProcess.tryFromJson(j({'title': ' '})), isNull);
      expect(LifeProcess.tryFromJson(j({'dims': <String>[]})), isNull);
      expect(LifeProcess.tryFromJson(j({'dims': ['soul']})), isNull);
      expect(LifeProcess.tryFromJson(j({'log': <Object>[]})), isNull);
      expect(LifeProcess.tryFromJson(j({'log': [{'t': 1, 's': 'dead'}]})), isNull);
      expect(LifeProcess.tryFromJson(j({'log': [{'t': 2, 's': 'active'}, {'t': 1, 's': 'paused'}]})), isNull); // не по порядку
      expect(LifeProcess.tryFromJson(j({'ct': 'вчера'})), isNull);
    });

    test('событие хранит ссылки на процессы', () {
      final e = LifeEvent(
        id: 'e',
        at: DateTime(2026, 11, 1),
        recordedAt: DateTime(2026, 11, 1),
        dimensions: [LifeDimension.mind],
        kind: LifeEventKind.action,
        title: 'занятие',
        processIds: ['p1', 'p1', 'p2'],
      );
      expect(e.processIds, ['p1', 'p2']);
      expect(LifeEvent.tryFromJson(e.toJson())!.processIds, ['p1', 'p2']);
      expect(LifeEvent.tryFromJson({...e.toJson(), 'procs': ['']}), isNull);
    });
  });

  group('контроллер', () {
    test('создание, проверка входных данных', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      expect(c.addProcess(title: ' ', dimensions: [LifeDimension.mind]), isNull);
      expect(c.addProcess(title: 'x', dimensions: const []), isNull);
      expect(c.addProcess(title: 'x', dimensions: [LifeDimension.mind], startedAt: now.add(const Duration(days: 2))), isNull);
      final id = c.addProcess(title: ' Изучение Java ', dimensions: [LifeDimension.mind], startedAt: DateTime(2026, 9, 1))!;
      final p = c.processById(id)!;
      expect(p.title, 'Изучение Java');
      expect(p.startedAt, DateTime(2026, 9, 1));
      expect(p.createdAt, now);
      expect(p.status, ProcessStatus.active);
    });

    test('статусы дописываются в журнал, прежние сохраняются', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      final id = c.addProcess(title: 'Набор массы', dimensions: [LifeDimension.body])!;
      expect(c.setProcessStatus(id, ProcessStatus.active), isFalse); // тот же статус
      expect(c.setProcessStatus(id, 'dead'), isFalse);
      tick(const Duration(days: 30));
      expect(c.setProcessStatus(id, ProcessStatus.paused, note: ' травма '), isTrue);
      tick(const Duration(days: 30));
      expect(c.setProcessStatus(id, ProcessStatus.completed), isTrue);
      final p = c.processById(id)!;
      expect(p.statusLog.map((s) => s.status), [ProcessStatus.active, ProcessStatus.paused, ProcessStatus.completed]);
      expect(p.statusLog[1].note, 'травма');
      expect(p.endedAt, now);
      expect(p.isOpen, isFalse);
    });

    test('правка описания не трогает журнал статусов', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      final id = c.addProcess(title: 'a', dimensions: [LifeDimension.mind])!;
      expect(c.updateProcess(id, title: '', dimensions: [LifeDimension.mind]), isFalse);
      expect(c.updateProcess(id, title: 'b', dimensions: const []), isFalse);
      expect(c.updateProcess(id, title: 'b', dimensions: [LifeDimension.mind, LifeDimension.material], description: 'd', goalIds: ['g']), isTrue);
      final p = c.processById(id)!;
      expect(p.title, 'b');
      expect(p.dimensions, [LifeDimension.mind, LifeDimension.material]);
      expect(p.statusLog, hasLength(1));
    });

    test('вложенное в процесс считается по его актуальным событиям', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      final p = c.addProcess(title: 'Java', dimensions: [LifeDimension.mind])!;
      final day1 = now.subtract(const Duration(days: 3));
      c.addEvent(title: 'урок 1', dimensions: [LifeDimension.mind], at: day1, processIds: [p], cost: const ResourceCost(minutes: 60));
      tick();
      final e2 = c.addEvent(title: 'урок 2', dimensions: [LifeDimension.mind], processIds: [p], cost: const ResourceCost(minutes: 45, money: 1000))!;
      tick();
      c.addEvent(title: 'не про Java', dimensions: [LifeDimension.mind], cost: const ResourceCost(minutes: 500));
      tick();
      final voided = c.addEvent(title: 'отменённое', dimensions: [LifeDimension.mind], processIds: [p], cost: const ResourceCost(minutes: 999))!;
      c.voidEvent(voided);

      var a = c.processActivityOf(p);
      expect(a.resources.events, 2);
      expect(a.resources.minutes, 105);
      expect(a.resources.moneyKnown, 1);
      expect(a.firstAt, day1);
      expect(c.eventsForProcess(p).map((e) => e.title), ['урок 1', 'урок 2']);

      // новая версия события без процесса — событие уходит из процесса, старая версия в истории
      tick();
      c.reviseEvent(e2, title: 'урок 2', dimensions: [LifeDimension.mind], kind: LifeEventKind.action, at: now, cost: const ResourceCost(minutes: 45));
      a = c.processActivityOf(p);
      expect(a.resources.events, 1);
      expect(a.resources.minutes, 60);
    });

    test('удаление процесса оставляет события и ссылку на него', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      final p = c.addProcess(title: 'Ремонт', dimensions: [LifeDimension.material])!;
      c.addEvent(title: 'купил краску', dimensions: [LifeDimension.material], processIds: [p]);
      expect(c.removeProcess(p), isTrue);
      expect(c.processes, isEmpty);
      expect(c.events.single.processIds, [p]);
    });
  });

  group('копии и хранилище', () {
    test('экспорт → импорт сохраняет процессы и связи событий', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      final p = c.addProcess(title: 'Java', dimensions: [LifeDimension.mind], goalIds: ['g'])!;
      tick();
      c.setProcessStatus(p, ProcessStatus.paused, note: 'пауза');
      c.addEvent(title: 'урок', dimensions: [LifeDimension.mind], processIds: [p]);
      final raw = c.exportBackup();
      final c2 = make(MemoryAppRepository());
      await c2.load();
      expect(c2.importBackup(raw), isTrue);
      expect(c2.exportBackup(), raw);
    });

    test('копия схемы 4 (без процессов) импортируется', () async {
      final j = AppData.blank(now: now).toJson()
        ..remove('processes')
        ..['schemaVersion'] = 4;
      final c = make(MemoryAppRepository());
      await c.load();
      expect(c.importBackup(jsonEncode(j)), isTrue);
      expect(c.processes, isEmpty);
    });

    test('строгий импорт отвергает битый процесс и повтор id', () {
      final ok = LifeProcess(
        id: 'p',
        title: 't',
        dimensions: [LifeDimension.mind],
        createdAt: now,
        statusLog: [ProcessStatusChange(at: now, status: ProcessStatus.active)],
      ).toJson();
      Map<String, dynamic> backup(List<Object> ps) => AppData.blank(now: now).toJson()..['processes'] = ps;
      expect(AppData.fromJson(backup([ok]), strict: true).processes, hasLength(1));
      expect(() => AppData.fromJson(backup([ok, ok]), strict: true), throwsFormatException);
      expect(() => AppData.fromJson(backup([{...ok, 'log': <Object>[]}]), strict: true), throwsFormatException);
    });

    test('SQLite: процессы и связи событий переживают перезапуск, правки пишутся точечно', () async {
      final db = await SqliteAppRepository.openDb(databaseFactoryFfi, inMemoryDatabasePath);
      addTearDown(db.close);
      SqliteAppRepository repo() => SqliteAppRepository(opener: () async => db);
      Future<String> reloaded() async {
        final c = make(repo());
        await c.load();
        return c.exportBackup();
      }

      final c = make(repo());
      await c.load();
      await c.flush();
      final p = c.addProcess(title: 'Java', dimensions: [LifeDimension.mind])!;
      c.addProcess(title: 'Бег', dimensions: [LifeDimension.body]);
      c.addEvent(title: 'урок', dimensions: [LifeDimension.mind], processIds: [p], cost: const ResourceCost(minutes: 30));
      await c.flush();
      expect(await reloaded(), c.exportBackup());

      final before = (await db.rawQuery('SELECT total_changes() AS n')).first['n'] as int;
      tick();
      c.setProcessStatus(p, ProcessStatus.completed);
      await c.flush();
      final after = (await db.rawQuery('SELECT total_changes() AS n')).first['n'] as int;
      expect(after - before, 1); // одна строка процесса
      expect(await reloaded(), c.exportBackup());

      c.removeProcess(p);
      await c.flush();
      expect(await reloaded(), c.exportBackup());
      expect((await db.rawQuery("SELECT COUNT(*) AS n FROM docs WHERE coll = 'processes'")).first['n'], 1);
    });
  });
}
