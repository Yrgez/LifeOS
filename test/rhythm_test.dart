import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app.dart';
import 'package:life_os/core/rhythm.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/models/life_event.dart';
import 'package:life_os/models/life_process.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:life_os/ui/screens/events_screen.dart';

void main() {
  late DateTime now;
  AppController make() => AppController(MemoryAppRepository(),
      clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n));
  // 18.11.2026 — среда; неделя с понедельника 16.11
  setUp(() => now = DateTime(2026, 11, 18, 12));

  test('слова и начало периода', () {
    expect([timesLabel(1), timesLabel(3), timesLabel(5), timesLabel(12), timesLabel(22)], ['1 раз', '3 раза', '5 раз', '12 раз', '22 раза']);
    expect(rhythmPeriodStart(DateTime(2026, 11, 18, 9), RhythmPeriod.week), DateTime(2026, 11, 16));
    expect(rhythmPeriodStart(DateTime(2026, 11, 16), RhythmPeriod.week), DateTime(2026, 11, 16));
    expect(rhythmPeriodStart(DateTime(2026, 11, 18), RhythmPeriod.month), DateTime(2026, 11));
    expect(rhythmLabel(ProcessRhythm(at: now, times: 3)), '3 раза в неделю');
  });

  test('модель: журнал ритма в JSON, неверный ритм отвергается', () {
    final c = make();
    final id = c.addProcess(title: 'Бег', dimensions: [LifeDimension.body], startedAt: DateTime(2026, 11, 2), rhythm: ProcessRhythm(at: now, times: 3))!;
    final p = c.processById(id)!;
    expect(p.rhythm!.times, 3);
    expect(p.rhythmLog.single.at, DateTime(2026, 11, 2)); // действует с начала процесса
    final j = p.toJson();
    expect(jsonEncode(LifeProcess.tryFromJson(jsonDecode(jsonEncode(j)) as Map<String, dynamic>)!.toJson()), jsonEncode(j));
    expect(LifeProcess.tryFromJson({...j, 'rh': [{'t': 1, 'n': 8, 'p': 'week'}]}), isNull);
    expect(LifeProcess.tryFromJson({...j, 'rh': [{'t': 1, 'n': 2, 'p': 'day'}]}), isNull);
    expect(LifeProcess.tryFromJson({...j, 'rh': [{'t': 5, 'n': 2, 'p': 'week'}, {'t': 1, 'n': 3, 'p': 'week'}]}), isNull);
    expect(jsonDecode(c.exportBackup())['schemaVersion'], greaterThanOrEqualTo(17));
  });

  test('по неделям: раз — день с событием, пауза не считается провалом, смена ритма не переписывает прошлое', () {
    final c = make();
    final id = c.addProcess(title: 'Бег', dimensions: [LifeDimension.body], startedAt: DateTime(2026, 10, 26), rhythm: ProcessRhythm(at: now, times: 3))!;
    void ev(int month, int day, [int hour = 8]) =>
        c.addEvent(title: 'Пробежка', dimensions: [LifeDimension.body], processIds: [id], at: DateTime(2026, month, day, hour));
    // неделя 26.10: три дня
    ev(10, 26);
    ev(10, 28);
    ev(10, 30);
    // неделя 02.11: один день, две записи
    ev(11, 3);
    ev(11, 3, 19);
    // неделя 09.11: пауза весь период
    now = DateTime(2026, 11, 9, 7);
    c.setProcessStatus(id, ProcessStatus.paused);
    now = DateTime(2026, 11, 16, 7);
    c.setProcessStatus(id, ProcessStatus.active);
    // с 16.11 ритм — 2 раза
    c.setProcessRhythm(id, 2);
    now = DateTime(2026, 11, 18, 12);
    ev(11, 16, 9);

    final spans = c.rhythmOf(id);
    expect(spans.length, 4); // недели до начала процесса не показываются
    final cur = spans[0], paused = spans[1], one = spans[2], full = spans[3];
    expect((cur.current, cur.done, cur.target, cur.reached), (true, 1, 2, false));
    expect((paused.active, paused.done), (false, 0));
    expect((one.done, one.target), (1, 3)); // старая неделя — по старому ритму
    expect((full.done, full.target, full.reached), (3, 3, true));
    expect(rhythmNowLabel(c.processById(id)!.rhythm!, cur), 'на этой неделе 1 из 2');
  });

  test('setProcessRhythm: повтор не пишется, 0 снимает, лишнее отвергается', () {
    final c = make();
    final id = c.addProcess(title: 'Чтение', dimensions: [LifeDimension.mind])!;
    expect(c.setProcessRhythm(id, 0), isTrue);
    expect(c.processById(id)!.rhythmLog, isEmpty);
    expect(c.setProcessRhythm(id, 8), isFalse);
    expect(c.setProcessRhythm(id, 20, period: RhythmPeriod.month), isTrue);
    expect(c.setProcessRhythm(id, 20, period: RhythmPeriod.month), isTrue);
    expect(c.processById(id)!.rhythmLog.length, 1);
    expect(c.setProcessRhythm(id, 0), isTrue);
    final p = c.processById(id)!;
    expect(p.rhythm, isNull);
    expect(p.rhythmLog.length, 2); // снятие тоже в журнале
    expect(c.setProcessRhythm('нет', 3), isFalse);
  });

  testWidgets('шапка процесса и «Сегодня» показывают ритм (360 px)', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(MemoryAppRepository(), clock: () => now, saveDelay: Duration.zero);
    await c.load();
    final id = c.addProcess(title: 'Бег', dimensions: [LifeDimension.body], startedAt: DateTime(2026, 9, 1), rhythm: ProcessRhythm(at: now, times: 3))!;
    c.addEvent(title: 'Пробежка', dimensions: [LifeDimension.body], processIds: [id], at: DateTime(2026, 11, 17, 8));
    await tester.pumpWidget(LifeOSApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.textContaining('на этой неделе 1 из 3'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: EventsScreen(controller: c, processId: id)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rhythm_strip')), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
