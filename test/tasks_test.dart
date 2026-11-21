import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catenna/app.dart';
import 'package:catenna/core/search.dart';
import 'package:catenna/data/app_data.dart';
import 'package:catenna/data/app_repository.dart';
import 'package:catenna/data/sqlite_app_repository.dart';
import 'package:catenna/models/life_event.dart';
import 'package:catenna/models/life_task.dart';
import 'package:catenna/state/app_controller.dart';
import 'package:catenna/ui/screens/events_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late DateTime now;
  AppController make([AppRepository? repo]) =>
      AppController(repo ?? MemoryAppRepository(), clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n));
  setUp(() => now = DateTime(2026, 11, 18, 12));

  group('модель', () {
    test('JSON туда-обратно; журнал обязан начинаться с постановки и идти по времени', () {
      final t = LifeTask(id: 't', title: 'Записаться к врачу', dimensions: ['body'], log: [
        TaskChange(at: now, step: TaskStep.created, day: '2026-11-18'),
        TaskChange(at: now.add(const Duration(hours: 1)), step: TaskStep.planned, day: '2026-11-20'),
      ]);
      expect((t.day, t.postponed, t.status), ('2026-11-20', 1, TaskStatus.open));
      expect(jsonEncode(LifeTask.tryFromJson(t.toJson())!.toJson()), jsonEncode(t.toJson()));
      final j = t.toJson();
      expect(LifeTask.tryFromJson({...j, 'log': [(j['log'] as List).last]}), isNull); // нет постановки
      expect(LifeTask.tryFromJson({...j, 'log': (j['log'] as List).reversed.toList()}), isNull); // не по времени
      expect(LifeTask.tryFromJson({...j, 'dims': []}), isNull);
      expect(LifeTask.tryFromJson({...j, 'log': [{'t': 1, 's': 'created', 'd': '2026-02-30'}]}), isNull);
    });
  });

  group('контроллер', () {
    test('постановка: измерения от процесса, прошлый день нельзя; списки дня, будущего и без даты', () {
      final c = make();
      final p = c.addProcess(title: 'Здоровье зубов', dimensions: [LifeDimension.body])!;
      expect(c.addTask(title: 'Вчерашнее', dimensions: ['mind'], day: DateTime(2026, 11, 17)), isNull);
      expect(c.addTask(title: 'Без измерений'), isNull);
      final a = c.addTask(title: 'Записаться к стоматологу', processId: p, day: now)!;
      expect(c.taskById(a)!.dimensions, ['body']);
      now = DateTime(2026, 11, 19, 9); // вчерашняя невыполненная остаётся в «сегодня»
      final b = c.addTask(title: 'Купить зубную нить', dimensions: ['body'], day: now)!;
      c.addTask(title: 'Сдать отчёт', dimensions: ['material'], day: DateTime(2026, 11, 21));
      c.addTask(title: 'Когда-нибудь — курс', dimensions: ['mind']);
      expect(c.tasksForToday.map((t) => t.id), [a, b]); // раньше назначенные — первыми
      expect(c.tasksUpcoming.single.title, 'Сдать отчёт');
      expect(c.tasksSomeday.single.title, 'Когда-нибудь — курс');
      expect(c.openTasksFor(processId: p).single.id, a);
    });

    test('правка задачи: поля меняются, пустое название и несуществующий процесс отвергаются', () {
      final c = make();
      final p = c.addProcess(title: 'Английский', dimensions: [LifeDimension.mind])!;
      final id = c.addTask(title: 'Урок', dimensions: ['mind'])!;
      expect(c.updateTask(id, title: '  ', dimensions: ['mind']), isFalse);
      expect(c.updateTask(id, title: 'Урок', dimensions: ['mind'], processId: 'нет такого'), isFalse);
      expect(c.updateTask('нет такой', title: 'x', dimensions: ['mind']), isFalse);
      expect(c.updateTask(id, title: ' Урок с репетитором ', dimensions: ['mind', 'material'], note: 'среда', processId: p, minutes: 60), isTrue);
      final t = c.taskById(id)!;
      expect([t.title, t.note, t.processId, t.minutes], ['Урок с репетитором', 'среда', p, 60]);
      expect(t.dimensions, containsAll(['mind', 'material']));
    });

    test('перенос дописывается в историю; тот же день — без записи', () {
      final c = make();
      final id = c.addTask(title: 'Отчёт', dimensions: ['material'], day: now)!;
      expect(c.planTask(id, now), isTrue);
      expect(c.taskById(id)!.log.length, 1);
      c.planTask(id, DateTime(2026, 11, 20));
      c.planTask(id, null);
      final t = c.taskById(id)!;
      expect((t.day, t.postponed, t.log.length), (null, 2, 3));
      expect(c.planTask(id, DateTime(2026, 11, 1)), isFalse);
    });

    test('«Сделано» — событие со ссылкой, процессом и целью, без придуманного времени; вернуть — событие отменено', () {
      final c = make();
      c.addGoal('Здоровые зубы', 'health', const []);
      final g = c.goals.single.id;
      now = now.add(const Duration(seconds: 1));
      final p = c.addProcess(title: 'Лечение', dimensions: [LifeDimension.body], defaultMinutes: 60)!;
      final id = c.addTask(title: 'Пломба', processId: p, goalId: g, minutes: 45, day: now, note: 'Клиника на Ленина')!;
      final ev = c.completeTask(id)!;
      final e = c.events.single;
      expect((e.id, e.title, e.note), (ev, 'Пломба', 'Клиника на Ленина'));
      expect(e.processIds, [p]);
      expect(e.goalIds, [g]);
      expect(e.refs.single.type, EventRef.task);
      expect(e.cost.minutes, isNull); // оценка 45 мин — не факт
      expect(c.taskById(id)!.status, TaskStatus.done);
      expect(c.tasksForToday, isEmpty);
      expect(c.tasksDoneRecently().single.id, id);
      expect(c.completeTask(id), isNull);

      expect(c.reopenTask(id), isTrue);
      expect(c.events, isEmpty); // событие отменено
      expect(c.allEvents.single.isVoided, isTrue); // но осталось в истории
      expect(c.taskById(id)!.status, TaskStatus.open);
    });

    test('отмена задачи и возврат; поиск находит задачи', () {
      final c = make();
      final id = c.addTask(title: 'Позвонить стоматологу', dimensions: ['body'], day: now)!;
      expect(c.cancelTask(id), isTrue);
      expect(c.tasksForToday, isEmpty);
      expect(c.search('стоматолог').single.title, 'Позвонить стоматологу · отменена');
      expect(c.reopenTask(id), isTrue);
      expect(c.tasksForToday.single.id, id);
      expect(c.search('стоматолог').single.kind, SearchKind.task);
    });

    test('хранится в SQLite и в копии; битая задача в строгом импорте отвергается', () async {
      final db = await SqliteAppRepository.openDb(databaseFactoryFfi, inMemoryDatabasePath);
      addTearDown(db.close);
      final c = make(SqliteAppRepository(opener: () async => db));
      await c.load();
      final id = c.addTask(title: 'Отчёт', dimensions: ['material'], day: now)!;
      c.completeTask(id);
      await c.flush();
      final c2 = make(SqliteAppRepository(opener: () async => db));
      await c2.load();
      expect(jsonEncode(c2.taskById(id)!.toJson()), jsonEncode(c.taskById(id)!.toJson()));
      expect(c2.events.single.refs.single.id, id);
      final j = jsonDecode(c.exportBackup()) as Map<String, dynamic>;
      expect(j['schemaVersion'], greaterThanOrEqualTo(22));
      expect(() => AppData.fromJson({...j, 'tasks': [{'id': 'x', 'title': 'y'}]}, strict: true), throwsFormatException);
    });
  });

  testWidgets('«Сегодня»: новая задача, «Сделано» и отмена; задачи на экране процесса (360 px)', (tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(MemoryAppRepository(), clock: () => now, saveDelay: Duration.zero);
    await c.load();
    await tester.pumpWidget(CatennaApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text('Задач на сегодня нет'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hub_add_task')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('task_title')), 'Записаться к врачу');
    await tester.tap(find.byKey(const ValueKey('task_dim_body')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('task_save')));
    await tester.tap(find.byKey(const ValueKey('task_save')));
    await tester.pumpAndSettle();
    final t = c.tasks.single;
    expect(find.text('Задачи на сегодня · 1'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('task_done_${t.id}')));
    await tester.pumpAndSettle();
    expect(c.taskById(t.id)!.status, TaskStatus.done);
    expect(c.events.single.title, 'Записаться к врачу');
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(c.taskById(t.id)!.status, TaskStatus.open);
    expect(c.events, isEmpty);

    final p = c.addProcess(title: 'Здоровье', dimensions: [LifeDimension.body])!;
    c.addTask(title: 'Сдать анализы', processId: p, day: now);
    await tester.pumpWidget(MaterialApp(home: EventsScreen(controller: c, processId: p)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tasks_block')), findsOneWidget);
    expect(find.text('Сдать анализы'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
