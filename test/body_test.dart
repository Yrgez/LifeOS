import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app.dart';
import 'package:life_os/core/body_stats.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/sqlite_app_repository.dart';
import 'package:life_os/models/body.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:life_os/ui/painters/anatomy_geometry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  var now = DateTime(2026, 11, 16, 9);
  setUp(() => now = DateTime(2026, 11, 16, 9));
  AppController make(AppRepository repo) =>
      AppController(repo, clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n));

  group('расчёты', () {
    test('ИМТ и категории ВОЗ', () {
      expect(bmi(80, 180), closeTo(24.69, 0.01));
      expect(bmi(null, 180), isNull);
      expect(bmi(80, null), isNull);
      expect(bmiCategory(17), 'ниже нормы');
      expect(bmiCategory(22), 'норма');
      expect(bmiCategory(27), 'выше нормы');
      expect(bmiCategory(31), 'ожирение');
    });

    test('изменение за 30 дней — от последнего замера не позже начала окна', () {
      WeightEntry w(String id, int daysAgo, double kg) => WeightEntry(id: id, at: now.subtract(Duration(days: daysAgo)), kg: kg);
      final list = [w('a', 40, 84), w('b', 31, 83.2), w('c', 10, 82), w('d', 1, 81.5)];
      final ch = weightChange(list, now, 30)!;
      expect(ch.from.id, 'b');
      expect(ch.delta, -1.7);
      expect(weightChange([w('x', 5, 80), w('y', 1, 79)], now, 30), isNull); // не с чем сравнить
    });

    test('замер: проверка границ и JSON', () {
      expect(WeightEntry.tryFromJson({'id': 'a', 't': 1, 'kg': 10}), isNull);
      expect(WeightEntry.tryFromJson({'id': 'a', 't': 1, 'kg': 500}), isNull);
      final e = WeightEntry.tryFromJson({'id': 'a', 't': 1, 'kg': 80.5})!;
      expect(WeightEntry.tryFromJson(e.toJson())!.kg, 80.5);
    });
  });

  test('фигура: нажатия попадают в свои группы мышц, обе стороны тела', () {
    String? front(double x, double y) => AnatomicalGeometry.groupAt(true, Offset(x, y));
    String? back(double x, double y) => AnatomicalGeometry.groupAt(false, Offset(x, y));
    expect(front(150, 190), 'chest');
    expect(front(220, 190), 'chest'); // правая сторона — зеркально
    expect(front(168, 240), 'abs');
    expect(front(100, 180), 'delts');
    expect(front(104, 240), 'biceps');
    expect(front(72, 320), 'forearms');
    expect(front(122, 440), 'quads');
    expect(front(157, 610), 'calves');
    expect(back(160, 180), 'traps');
    expect(back(135, 260), 'lats');
    expect(back(105, 240), 'triceps');
    expect(back(150, 395), 'glutes');
    expect(back(130, 480), 'hamstrings');
    expect(back(125, 600), 'calves');
    expect(front(185, 60), isNull); // голова — не мышца
    expect(front(40, 430), isNull); // кисть
    expect(front(10, 10), isNull); // мимо фигуры
    expect(front(140, 330), isNull); // косая мышца рисуется, но группой не является
    // все группы приложения есть хотя бы на одной стороне, и у каждой группы списка есть сегменты
    expect({...AnatomicalGeometry.frontGroups, ...AnatomicalGeometry.backGroups}, containsAll(MuscleGroupIds.all));
    for (final front in [true, false]) {
      expect({for (final s in AnatomicalGeometry.shapesFor(front)) if (s.group != null) s.group}, AnatomicalGeometry.groupsFor(front).toSet());
    }
  });

  group('контроллер', () {
    test('замеры, удаление с возвратом, рост и цель', () async {
      final c = make(MemoryAppRepository());
      await c.load();
      expect(c.addWeight(10), isNull);
      expect(c.addWeight(80, at: now.add(const Duration(days: 1))), isNull); // не в будущем
      c.addWeight(82.04, at: now.subtract(const Duration(days: 3)));
      final id = c.addWeight(81.5)!;
      expect(c.weights.map((w) => w.kg), [82.0, 81.5]); // округление до 0,1 и порядок по времени
      expect(c.bodyMassIndex, isNull);
      expect(c.setHeight(10), isFalse);
      expect(c.setHeight(180), isTrue);
      expect(c.bodyMassIndex, closeTo(25.15, 0.01));
      final removed = c.removeWeight(id)!;
      expect(c.latestWeightEntry!.kg, 82.0);
      c.restoreWeight(removed);
      expect(c.latestWeightEntry!.kg, 81.5);
      expect(c.setBodyGoal('bulk'), isFalse);
      expect(c.setBodyGoal(BodyGoal.lose), isTrue);
      c.resetAllData();
      expect(c.weights, isEmpty); // замеры — данные
      expect(c.heightCm, 180); // рост и цель — личные настройки
      expect(c.bodyGoal, BodyGoal.lose);
    });

    test('копия и SQLite сохраняют тело; строгий импорт отвергает неверные значения', () async {
      final db = await SqliteAppRepository.openDb(databaseFactoryFfi, inMemoryDatabasePath);
      addTearDown(db.close);
      final c = make(SqliteAppRepository(opener: () async => db));
      await c.load();
      c.addWeight(80);
      c.setHeight(175);
      c.setBodyGoal(BodyGoal.gain);
      await c.flush();
      final c2 = make(SqliteAppRepository(opener: () async => db));
      await c2.load();
      expect(c2.exportBackup(), c.exportBackup());

      final j = jsonDecode(c.exportBackup()) as Map<String, dynamic>;
      expect(AppData.fromJson(j, strict: true).heightCm, 175);
      expect(() => AppData.fromJson({...j, 'heightCm': 20}, strict: true), throwsFormatException);
      expect(() => AppData.fromJson({...j, 'bodyGoal': 'bulk'}, strict: true), throwsFormatException);
      expect(() => AppData.fromJson({...j, 'weights': [{'id': 'x', 't': 1, 'kg': 5}]}, strict: true), throwsFormatException);
      expect(AppData.fromJson({...j}..remove('heightCm')..remove('bodyGoal')..remove('weights')).weights, isEmpty); // старые копии
    });
  });

  testWidgets('вкладка «Тело»: замер веса и цель через интерфейс', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(MemoryAppRepository(), saveDelay: Duration.zero);
    await c.load();
    await tester.pumpWidget(LifeOSApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab_body')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add_weight')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '78,4');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Записать'));
    await tester.pumpAndSettle();
    expect(c.latestWeightEntry!.kg, 78.4);
    expect(find.text('78,4 кг'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('goal_maintain')));
    await tester.pumpAndSettle();
    expect(c.bodyGoal, BodyGoal.maintain);
    await tester.tap(find.byKey(const ValueKey('goal_maintain')));
    await tester.pumpAndSettle();
    expect(c.bodyGoal, isNull); // повторное нажатие снимает цель

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}

/// Группы мышц приложения (как в MuscleGroup.defaultRecoveryHours).
class MuscleGroupIds {
  static const all = ['delts', 'chest', 'abs', 'biceps', 'forearms', 'quads', 'traps', 'lats', 'triceps', 'glutes', 'hamstrings', 'calves'];
}
