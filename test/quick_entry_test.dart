import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/models/life_event.dart';
import 'package:life_os/models/life_process.dart';
import 'package:life_os/state/app_controller.dart';

void main() {
  late DateTime now;
  AppController make() => AppController(MemoryAppRepository(), clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n));
  setUp(() => now = DateTime(2026, 11, 18, 19));

  test('повтор события: те же поля сегодня, без ссылок на записи; обзор не повторяется', () async {
    final c = make();
    await c.load();
    final p = c.addProcess(title: 'Java', dimensions: [LifeDimension.mind])!;
    final a = c.addEvent(
      title: 'Урок',
      dimensions: [LifeDimension.mind],
      at: now.subtract(const Duration(days: 2)),
      processIds: [p],
      cost: const ResourceCost(minutes: 60, energy: 3),
      refs: [const EventRef(EventRef.transaction, 't1')],
    )!;
    now = now.add(const Duration(minutes: 1));
    final b = c.eventById(c.repeatEvent(a)!)!;
    expect(b.title, 'Урок');
    expect(b.at, now);
    expect(b.processIds, [p]);
    expect(b.cost, const ResourceCost(minutes: 60, energy: 3));
    expect(b.refs, isEmpty);
    final r = c.saveWeekReview(['итог', '', ''])!;
    expect(c.repeatEvent(r), isNull);
  });

  test('обычная длительность процесса: хранится, проверяется, переживает копию', () async {
    final c = make();
    await c.load();
    final p = c.addProcess(title: 'Java', dimensions: [LifeDimension.mind], defaultMinutes: 90)!;
    expect(c.processById(p)!.defaultMinutes, 90);
    expect(c.addProcess(title: 'x', dimensions: [LifeDimension.mind], defaultMinutes: 0), isNull);
    c.updateProcess(p, title: 'Java', dimensions: [LifeDimension.mind], defaultMinutes: 45);
    expect(c.processById(p)!.defaultMinutes, 45);
    final j = c.processById(p)!.toJson();
    expect(LifeProcess.tryFromJson(j)!.defaultMinutes, 45);
    expect(LifeProcess.tryFromJson({...j, 'defMin': -5}), isNull);
    expect(LifeProcess.tryFromJson({...j}..remove('defMin'))!.defaultMinutes, isNull);
  });

  test('тренировка дня: событие со ссылками на подходы, дополнение новой версией без дублей', () async {
    final c = make();
    await c.load();
    c.logWorkout('chest', 80, 5);
    c.logWorkout('biceps', 20, 10);
    expect(c.unrecordedSets(now), hasLength(2));
    final id = c.recordWorkoutEvent(now)!;
    final e = c.eventById(id)!;
    expect(e.title, 'Тренировка: Грудные мышцы, Бицепс');
    expect(e.source, EventSource.auto);
    expect(e.dimensions, [LifeDimension.body]);
    expect(e.refs, hasLength(2));
    expect(e.note, 'Подходов: 2 · объём 600 кг (из журнала тренировок)');
    expect(c.unrecordedSets(now), isEmpty);
    expect(c.recordWorkoutEvent(now), isNull);

    now = now.add(const Duration(minutes: 10));
    c.logWorkout('chest', 85, 5);
    final v2 = c.eventById(c.recordWorkoutEvent(now)!)!;
    expect(v2.supersedesId, id); // новая версия, а не второе событие
    expect(v2.refs, hasLength(3));
    expect(c.events.where((x) => x.source == EventSource.auto), hasLength(1));
  });

  test('операция → событие: материальное, деньги расхода, ссылка; повторно не дублируется', () async {
    final c = make();
    await c.load();
    c.addTransaction(categoryId: 'shopping', amount: 15000, note: 'Курс Java');
    final t = c.transactions.single;
    final id = c.eventFromTransaction(t.id)!;
    final e = c.eventById(id)!;
    expect(e.title, 'Курс Java');
    expect(e.dimensions, [LifeDimension.material]);
    expect(e.cost.money, 15000);
    expect(e.refs.single.id, t.id);
    expect(c.eventFromTransaction(t.id), id);
    expect(jsonDecode(c.exportBackup())['schemaVersion'], kSchemaVersion);
  });

  testWidgets('«Тело»: плитка тренировки записывает событие', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(MemoryAppRepository(), saveDelay: Duration.zero);
    await c.load();
    c.logWorkout('chest', 80, 5);
    await tester.pumpWidget(LifeOSApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab_body')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('record_workout')));
    await tester.pumpAndSettle();
    expect(c.events.single.title, 'Тренировка: Грудные мышцы');
    expect(find.byKey(const ValueKey('workout_event_tile')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
