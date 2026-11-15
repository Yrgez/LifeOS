import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/life_events.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/sqlite_app_repository.dart';
import 'package:life_os/models/life_event.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DateTime now;
  void tick() => now = now.add(const Duration(minutes: 1));

  AppController make(AppRepository repo, {int maxEvents = kMaxLifeEvents}) => AppController(
        repo,
        clock: () => now,
        saveDelay: const Duration(days: 1),
        maxEvents: maxEvents,
        initialData: (n) => AppData.blank(now: n),
      );

  LifeEvent ev(String id, {DateTime? at, String? sup, List<String> dims = const [LifeDimension.mind], ResourceCost cost = ResourceCost.none, DateTime? voided}) =>
      LifeEvent(
        id: id,
        at: at ?? DateTime(2026, 10, 1),
        recordedAt: at ?? DateTime(2026, 10, 1),
        dimensions: dims,
        kind: LifeEventKind.action,
        title: 'событие $id',
        cost: cost,
        supersedesId: sup,
        voidedAt: voided,
      );

  setUp(() => now = DateTime(2026, 11, 15, 12));

  group('модель', () {
    test('JSON: круг без потерь', () {
      final e = LifeEvent(
        id: 'e1',
        at: DateTime(2026, 11, 1, 9),
        recordedAt: DateTime(2026, 11, 2, 10),
        dimensions: [LifeDimension.material, LifeDimension.mind, LifeDimension.mind],
        kind: LifeEventKind.decision,
        title: 'Купил курс по Java',
        note: 'ради смены профессии',
        cost: const ResourceCost(minutes: 30, money: 15000, energy: 2),
        goalIds: ['g1', 'g1', 'g2'],
        refs: [const EventRef(EventRef.transaction, 'tx1')],
        supersedesId: 'e0',
        voidedAt: DateTime(2026, 11, 3),
      );
      expect(e.dimensions, [LifeDimension.mind, LifeDimension.material]); // порядок и без повторов
      expect(e.goalIds, ['g1', 'g2']);
      final back = LifeEvent.tryFromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>)!;
      expect(jsonEncode(back.toJson()), jsonEncode(e.toJson()));
      expect(back.cost, e.cost);
    });

    test('«не указано» и ноль — разные значения', () {
      final empty = LifeEvent.tryFromJson(ev('a').toJson())!;
      expect(empty.cost.minutes, isNull);
      final zero = LifeEvent.tryFromJson(ev('b', cost: const ResourceCost(minutes: 0)).toJson())!;
      expect(zero.cost.minutes, 0);
    });

    test('битые записи отвергаются, а не «чинятся»', () {
      Map<String, dynamic> j(Map<String, dynamic> patch) => {...ev('x').toJson(), ...patch};
      expect(LifeEvent.tryFromJson(j({'dims': <String>[]})), isNull);
      expect(LifeEvent.tryFromJson(j({'dims': ['soul']})), isNull);
      expect(LifeEvent.tryFromJson(j({'kind': 'party'})), isNull);
      expect(LifeEvent.tryFromJson(j({'title': '  '})), isNull);
      expect(LifeEvent.tryFromJson(j({'cost': {'en': 7}})), isNull);
      expect(LifeEvent.tryFromJson(j({'cost': {'rub': -5}})), isNull);
      expect(LifeEvent.tryFromJson(j({'cost': {'min': 1.5}})), isNull);
      expect(LifeEvent.tryFromJson(j({'refs': [{'type': 'unknown', 'id': '1'}]})), isNull);
      expect(LifeEvent.tryFromJson(j({'sup': 'x'})), isNull); // версия самого себя
      expect(LifeEvent.tryFromJson(j({'void': 'вчера'})), isNull);
      expect(LifeEvent.tryFromJson(j({'t': null})), isNull);
    });

    test('проверка журнала: повторы, висячие версии, развилки, циклы', () {
      expect(eventJournalProblem([ev('a'), ev('b', sup: 'a')]), isNull);
      expect(eventJournalProblem([ev('a'), ev('a')]), contains('повторяющийся'));
      expect(eventJournalProblem([ev('b', sup: 'a')]), contains('несуществующего'));
      expect(eventJournalProblem([ev('a'), ev('b', sup: 'a'), ev('c', sup: 'a')]), contains('несколько'));
      expect(eventJournalProblem([ev('a', sup: 'b'), ev('b', sup: 'a')]), contains('цикл'));
    });
  });

  group('чтение журнала', () {
    test('актуальные события, цепочка версий', () {
      final list = [ev('a'), ev('b', sup: 'a'), ev('c', sup: 'b'), ev('d', voided: DateTime(2026, 10, 2)), ev('e')];
      expect(currentEvents(list).map((e) => e.id), ['c', 'e']);
      expect(revisionChain(list, 'b').map((e) => e.id), ['a', 'b', 'c']);
      expect(latestRevision(list, 'a')!.id, 'c');
      expect(revisionChain(list, 'нет'), isEmpty);
    });

    test('сводка ресурсов: суммы известного и счёт неуказанного', () {
      final list = [
        ev('a', at: DateTime(2026, 10, 1), dims: [LifeDimension.body], cost: const ResourceCost(minutes: 60, energy: 4)),
        ev('b', at: DateTime(2026, 10, 2), dims: [LifeDimension.body, LifeDimension.material], cost: const ResourceCost(minutes: 30, money: 5000, energy: 4)),
        ev('c', at: DateTime(2026, 10, 3), dims: [LifeDimension.mind]),
        ev('d', at: DateTime(2026, 11, 1), dims: [LifeDimension.body], cost: const ResourceCost(minutes: 999)), // вне периода
      ];
      final from = DateTime(2026, 10, 1), to = DateTime(2026, 11, 1);
      final all = summarizeResources(list, from: from, to: to);
      expect(all.events, 3);
      expect(all.minutes, 90);
      expect(all.minutesKnown, 2);
      expect(all.moneyKnown, 1);
      expect(all.energy, {4: 2});
      final body = summarizeResources(list, from: from, to: to, dimension: LifeDimension.body);
      expect(body.events, 2);
      expect(summarizeResources(list, from: from, to: to, dimension: LifeDimension.material).money, 5000);
      expect(summarizeResources(list, from: from, to: to, dimension: LifeDimension.mind).minutesKnown, 0);
    });
  });

  group('контроллер', () {
    test('добавление, проверка входных данных', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      expect(c.addEvent(title: '  ', dimensions: [LifeDimension.mind]), isNull);
      expect(c.addEvent(title: 'x', dimensions: const []), isNull);
      expect(c.addEvent(title: 'x', dimensions: ['soul']), isNull);
      expect(c.addEvent(title: 'x', dimensions: [LifeDimension.mind], cost: const ResourceCost(energy: 9)), isNull);
      expect(c.addEvent(title: 'x', dimensions: [LifeDimension.mind], at: now.add(const Duration(days: 1))), isNull);
      final id = c.addEvent(
        title: ' Занятие Java ',
        dimensions: [LifeDimension.mind],
        at: now.subtract(const Duration(days: 2)),
        cost: const ResourceCost(minutes: 90, energy: 3),
      );
      expect(id, isNotNull);
      final e = c.eventById(id!)!;
      expect(e.title, 'Занятие Java');
      expect(e.recordedAt, now); // записано задним числом — это видно
      expect(e.at, now.subtract(const Duration(days: 2)));
      expect(c.events, hasLength(1));
    });

    test('правка — новая версия, прежняя в истории', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      final id = c.addEvent(title: 'Тренировка', dimensions: [LifeDimension.body])!;
      tick();
      final v2 = c.reviseEvent(id, title: 'Тренировка ног', dimensions: [LifeDimension.body], kind: LifeEventKind.action, at: now)!;
      expect(c.events.map((e) => e.id), [v2]);
      expect(c.allEvents, hasLength(2));
      expect(c.eventRevisions(id).map((e) => e.id), [id, v2]);
      expect(c.eventById(v2)!.supersedesId, id);
      // старую версию править нельзя — только последнюю
      expect(c.reviseEvent(id, title: 'x', dimensions: [LifeDimension.body], kind: LifeEventKind.action, at: now), isNull);
    });

    test('отмена и возврат, удаление навсегда — всей цепочки', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      final id = c.addEvent(title: 'Покупка', dimensions: [LifeDimension.material])!;
      tick();
      final v2 = c.reviseEvent(id, title: 'Покупка штанги', dimensions: [LifeDimension.material, LifeDimension.body], kind: LifeEventKind.action, at: now)!;
      expect(c.voidEvent(id), isTrue); // по любой версии отменяется последняя
      expect(c.events, isEmpty);
      expect(c.eventById(v2)!.isVoided, isTrue);
      expect(c.allEvents, hasLength(2));
      expect(c.reviseEvent(v2, title: 'x', dimensions: [LifeDimension.body], kind: LifeEventKind.action, at: now), isNull);
      expect(c.unvoidEvent(v2), isTrue);
      expect(c.events.single.id, v2);

      final other = c.addEvent(title: 'Другое', dimensions: [LifeDimension.mind])!;
      expect(c.purgeEvent(v2), 2);
      expect(c.allEvents.map((e) => e.id), [other]);
    });

    test('предел журнала: новые не принимаются, старые не вытесняются', () async {
      final c = make(MemoryAppRepository(), maxEvents: 2);
      await c.load();
      final a = c.addEvent(title: 'a', dimensions: [LifeDimension.mind]);
      c.addEvent(title: 'b', dimensions: [LifeDimension.mind]);
      expect(c.eventsFull, isTrue);
      expect(c.addEvent(title: 'c', dimensions: [LifeDimension.mind]), isNull);
      expect(c.eventById(a!), isNotNull);
    });

    test('события по цели переживают удаление цели', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      c.addGoal('Стать Java-разработчиком', 'Карьера', ['Основы']);
      final g = c.goals.single.id;
      c.addEvent(title: 'Курс', dimensions: [LifeDimension.mind], goalIds: [g]);
      expect(c.eventsForGoal(g), hasLength(1));
      c.removeGoal(g);
      expect(c.events.single.goalIds, [g]);
    });
  });

  group('резервная копия', () {
    Map<String, dynamic> backup(List<Map<String, dynamic>> events) {
      final j = AppData.blank(now: DateTime(2026, 11, 15)).toJson();
      j['events'] = events;
      return j;
    }

    test('экспорт → импорт сохраняет события и версии', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      final id = c.addEvent(title: 'a', dimensions: [LifeDimension.mind], cost: const ResourceCost(money: 100));
      tick();
      c.reviseEvent(id!, title: 'b', dimensions: [LifeDimension.mind], kind: LifeEventKind.milestone, at: now);
      final raw = c.exportBackup();
      final c2 = make(MemoryAppRepository());
      await c2.load();
      expect(c2.importBackup(raw), isTrue);
      expect(c2.exportBackup(), raw);
    });

    test('старая копия (схема 3, без событий) импортируется с пустым журналом', () async {
      final j = AppData.blank(now: DateTime(2026, 11, 15)).toJson()
        ..remove('events')
        ..['schemaVersion'] = 3;
      final c = make(MemoryAppRepository());
      await c.load();
      expect(c.importBackup(jsonEncode(j)), isTrue);
      expect(c.allEvents, isEmpty);
    });

    test('строгий импорт отвергает битые события, повторы и нарушенные версии', () {
      final ok = ev('a').toJson();
      expect(() => AppData.fromJson(backup([ok, {...ok, 'kind': 'x', 'id': 'b'}]), strict: true), throwsFormatException);
      expect(() => AppData.fromJson(backup([ok, ok]), strict: true), throwsFormatException);
      expect(() => AppData.fromJson(backup([ev('b', sup: 'нет').toJson()]), strict: true), throwsFormatException);
      expect(() => AppData.fromJson(backup([for (var i = 0; i <= kMaxLifeEvents; i++) ev('e$i').toJson()]), strict: true), throwsFormatException);
    });

    test('обычная загрузка пропускает только битую запись, остальная история цела', () {
      final d = AppData.fromJson(backup([ev('a').toJson(), {'id': 'битая'}, ev('c').toJson()]));
      expect(d.events.map((e) => e.id), ['a', 'c']);
    });
  });

  group('SQLite', () {
    late Database db;
    setUp(() async => db = await SqliteAppRepository.openDb(databaseFactoryFfi, inMemoryDatabasePath));
    tearDown(() => db.close());

    SqliteAppRepository repo() => SqliteAppRepository(opener: () async => db);
    Future<int> count() async => (await db.rawQuery('SELECT COUNT(*) AS n FROM life_events')).first['n'] as int;
    Future<String> reloaded() async {
      final c = make(repo());
      await c.load();
      return c.exportBackup();
    }

    test('добавление, версия, отмена, удаление доходят до базы точечно', () async {
      final c = make(repo());
      await c.load();
      await c.flush();
      final a = c.addEvent(title: 'a', dimensions: [LifeDimension.body], cost: const ResourceCost(minutes: 45))!;
      tick();
      c.addEvent(title: 'b', dimensions: [LifeDimension.mind]);
      await c.flush();
      expect(await count(), 2);
      expect(await reloaded(), c.exportBackup());

      tick();
      final a2 = c.reviseEvent(a, title: 'a2', dimensions: [LifeDimension.body], kind: LifeEventKind.action, at: now)!;
      c.voidEvent(a2);
      await c.flush();
      expect(await count(), 3);
      expect(await reloaded(), c.exportBackup());

      c.purgeEvent(a);
      await c.flush();
      expect(await count(), 1);
      expect(await reloaded(), c.exportBackup());
    });

    test('импорт и сброс переписывают журнал событий целиком', () async {
      final c = make(repo());
      await c.load();
      c.addEvent(title: 'a', dimensions: [LifeDimension.body]);
      await c.flush();
      c.resetAllData();
      await c.flush();
      expect(await count(), 0);
      expect(await reloaded(), c.exportBackup());
    });

    test('миграция базы v1 → v2: таблица событий создаётся, данные целы', () async {
      final dir = await Directory.systemTemp.createTemp('life_os_ev');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/v1.db';
      // данные пишет текущая версия, затем база «откатывается» к формату v1: без таблицы событий
      final v1 = await SqliteAppRepository.openDb(databaseFactoryFfi, path);
      final c1 = make(SqliteAppRepository(opener: () async => v1));
      await c1.load();
      c1.logWorkout('chest', 80, 5);
      await c1.flush();
      await v1.execute('DROP TABLE life_events');
      await v1.execute('DROP TABLE day_snapshots'); // в v1 не было и её
      await v1.setVersion(1);
      await v1.close();

      final v2 = await SqliteAppRepository.openDb(databaseFactoryFfi, path);
      addTearDown(v2.close);
      expect(await v2.getVersion(), kDbVersion);
      final c2 = make(SqliteAppRepository(opener: () async => v2));
      await c2.load();
      expect(c2.sets, hasLength(1));
      c2.addEvent(title: 'после миграции', dimensions: [LifeDimension.mind]);
      await c2.flush();
      expect((await v2.rawQuery('SELECT COUNT(*) AS n FROM life_events')).first['n'], 1);
    });
  });
}
