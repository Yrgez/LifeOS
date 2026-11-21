import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catenna/app.dart';
import 'package:catenna/core/sections.dart';
import 'package:catenna/data/app_data.dart';
import 'package:catenna/data/app_repository.dart';
import 'package:catenna/data/sqlite_app_repository.dart';
import 'package:catenna/state/app_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  final now = DateTime(2026, 11, 18, 12);
  AppController make([AppRepository? repo]) =>
      AppController(repo ?? MemoryAppRepository(), clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n));

  test('по умолчанию всё видно; скрытие и показ; неизвестный раздел отвергается', () {
    final c = make();
    expect(Sections.all.every((s) => c.isShown(s.id)), isTrue);
    expect(c.setSectionShown(Sections.workouts, false), isTrue);
    expect(c.isShown(Sections.workouts), isFalse);
    expect(c.setSectionShown(Sections.workouts, false), isTrue); // повтор — без изменений
    expect(c.hiddenSections, {Sections.workouts});
    expect(c.setSectionShown('события', false), isFalse); // ядро не скрывается
    expect(c.setSectionShown(Sections.workouts, true), isTrue);
    expect(c.hiddenSections, isEmpty);
  });

  test('скрытие не трогает данные: подходы и вес остаются, в копии — список разделов', () {
    final c = make();
    c.logWorkout('chest', 80, 5);
    c.addWeight(80);
    c.setSectionShown(Sections.workouts, false);
    c.setSectionShown(Sections.weight, false);
    expect(c.sets, isNotEmpty);
    expect(c.weights, isNotEmpty);
    final j = jsonDecode(c.exportBackup()) as Map<String, dynamic>;
    expect(j['hiddenSections'], [Sections.weight, Sections.workouts]);
    expect(j['schemaVersion'], greaterThanOrEqualTo(18));
    // раздел из более новой версии не ломает чтение
    expect(AppData.fromJson({...j, 'hiddenSections': ['будущий', Sections.graph]}).hiddenSections, {Sections.graph});
    expect(() => AppData.fromJson({...j, 'hiddenSections': [1]}, strict: true), throwsFormatException);
  });

  test('хранится в SQLite', () async {
    final db = await SqliteAppRepository.openDb(databaseFactoryFfi, inMemoryDatabasePath);
    addTearDown(db.close);
    final c = make(SqliteAppRepository(opener: () async => db));
    await c.load();
    c.setSectionShown(Sections.salary, false);
    await c.flush();
    final c2 = make(SqliteAppRepository(opener: () async => db));
    await c2.load();
    expect(c2.isShown(Sections.salary), isFalse);
    expect(c2.isShown(Sections.graph), isTrue);
  });

  testWidgets('скрытые разделы пропадают с экранов, переключатель в настройках (360 px)', (tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(MemoryAppRepository(), clock: () => now, saveDelay: Duration.zero);
    await c.load();
    await tester.pumpWidget(CatennaApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recovery_tile')), findsOneWidget);
    expect(find.byKey(const ValueKey('steps_tile')), findsOneWidget);

    c.setSectionShown(Sections.workouts, false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recovery_tile')), findsNothing);
    expect(find.byKey(const ValueKey('steps_tile')), findsOneWidget); // одна плитка на всю ширину

    c.setSectionShown(Sections.weight, false);
    await tester.tap(find.byKey(const ValueKey('tab_body')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('body_all_hidden')), findsOneWidget);
    expect(find.byKey(const ValueKey('weight_tile')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tab_mind')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('open_graph')), findsOneWidget);
    c.setSectionShown(Sections.graph, false);
    c.setSectionShown(Sections.experiments, false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('open_graph')), findsNothing);
    expect(find.byKey(const ValueKey('open_experiments')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tab_material')));
    await tester.pumpAndSettle();
    expect(find.text('Рост зарплаты'), findsOneWidget);
    c.setSectionShown(Sections.salary, false);
    await tester.pumpAndSettle();
    expect(find.text('Рост зарплаты'), findsNothing);

    // включить обратно из настроек
    await tester.tap(find.byKey(const ValueKey('tab_today')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('section_graph')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('section_graph')));
    await tester.pumpAndSettle();
    expect(c.isShown(Sections.graph), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
