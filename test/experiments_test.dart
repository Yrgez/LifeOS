import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app.dart';
import 'package:life_os/core/experiments.dart';
import 'package:life_os/core/life_events.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/health_source.dart';
import 'package:life_os/data/sqlite_app_repository.dart';
import 'package:life_os/models/experiment.dart';
import 'package:life_os/models/life_event.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late DateTime now;
  AppController make({AppRepository? repo, HealthDataSource? health}) => AppController(repo ?? MemoryAppRepository(),
      clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n), health: health);
  setUp(() => now = DateTime(2026, 11, 18, 12));

  group('внимание', () {
    test('отметка — только вместе со временем; сводка считает минуты в фокусе и урывками', () {
      expect(const ResourceCost(attention: Attention.focused).isValid, isFalse);
      expect(const ResourceCost(minutes: 30, attention: 'x').isValid, isFalse);
      expect(ResourceCost.tryFromJson({'min': 30, 'att': 'focus'}), const ResourceCost(minutes: 30, attention: Attention.focused));
      expect(ResourceCost.tryFromJson({'min': 30, 'att': 5}), isNull);

      final c = make();
      c.addEvent(title: 'Код', dimensions: [LifeDimension.material], cost: const ResourceCost(minutes: 90, attention: Attention.focused));
      c.addEvent(title: 'Почта', dimensions: [LifeDimension.material], cost: const ResourceCost(minutes: 30, attention: Attention.scattered));
      c.addEvent(title: 'Звонок', dimensions: [LifeDimension.material], cost: const ResourceCost(minutes: 20));
      final s = summarizeEvents(c.events);
      expect((s.focusedMinutes, s.scatteredMinutes, s.attentionKnown, s.minutesKnown), (90, 30, 2, 3));
      expect(c.exportCsv('events'), contains('В фокусе'));
    });
  });

  group('эксперимент', () {
    test('модель: проверка и JSON туда-обратно', () {
      final x = Experiment(
          id: 'e', title: 'Без экрана', metric: ExperimentMetric.sleep, startedAt: DateTime(2026, 11, 10, 15), days: 7, createdAt: now);
      expect(x.startedAt, DateTime(2026, 11, 10));
      expect(x.isValid, isTrue);
      expect(jsonEncode(Experiment.tryFromJson(x.toJson())!.toJson()), jsonEncode(x.toJson()));
      expect(Experiment.tryFromJson({...x.toJson(), 'days': 1}), isNull);
      expect(Experiment.tryFromJson({...x.toJson(), 'metric': 'mood'}), isNull);
      expect(Experiment.tryFromJson({...x.toJson(), 'metric': 'process'}), isNull); // нет процесса
      expect(Experiment.tryFromJson({...x.toJson(), 'start': DateTime(2026, 11, 10, 3).millisecondsSinceEpoch}), isNull);
    });

    test('сравнение периодов по снимкам дня', () {
      final x = Experiment(
          id: 'e', title: 'Без экрана', metric: ExperimentMetric.sleep, startedAt: DateTime(2026, 11, 11), days: 7, createdAt: now);
      final day = {'2026-11-04': 400, '2026-11-05': 410, '2026-11-07': 420, '2026-11-11': 450, '2026-11-12': 470, '2026-11-13': 460, '2026-11-14': 480};
      final data = AppData.fromJson({
        'snapshots': [for (final e in day.entries) {'day': e.key, 'sleep': e.value}],
      });
      final r = experimentResult(x, snapshots: data.snapshots, weights: const [], currentEvents: const [], now: now);
      expect(r.before.values, [400, 410, 420]);
      expect(r.before.days, 7);
      expect(r.before.median, 410);
      expect(r.after!.values, [450, 470, 460, 480]);
      expect(r.after!.median, 465);
      expect((r.after!.min, r.after!.max), (450, 480));
      expect(r.after!.to, DateTime(2026, 11, 18)); // плановый конец

      // эксперимент ещё не начался — есть только «до»
      final later = Experiment(id: 'l', title: 't', metric: ExperimentMetric.steps, startedAt: DateTime(2026, 11, 25), days: 7, createdAt: now);
      expect(experimentResult(later, snapshots: data.snapshots, weights: const [], currentEvents: const [], now: now).after, isNull);
    });

    test('контроллер: создание, формулировки, досрочное завершение, удаление', () {
      final c = make();
      expect(c.addExperiment(title: 'Старт', metric: ExperimentMetric.sleep, startedAt: DateTime(2025, 1, 1), days: 7), isNull); // слишком давно
      expect(c.addExperiment(title: ' ', metric: ExperimentMetric.sleep, startedAt: now, days: 7), isNull);
      expect(c.addExperiment(title: 'П', metric: ExperimentMetric.process, processId: 'нет', startedAt: now, days: 7), isNull);
      final id = c.addExperiment(title: 'Ложусь до 23', hypothesis: 'больше сна', metric: ExperimentMetric.sleep, startedAt: DateTime(2026, 11, 15), days: 14)!;
      expect(c.experimentById(id)!.isFinished(now), isFalse);
      expect(c.updateExperimentText(id, conclusion: 'Засыпаю быстрее'), isTrue);
      expect(c.endExperiment(id), isTrue);
      final x = c.experimentById(id)!;
      expect(x.end, DateTime(2026, 11, 19));
      expect(x.conclusion, 'Засыпаю быстрее');
      expect(c.endExperiment(id), isFalse);
      expect(c.removeExperiment(id), isTrue);
      expect(c.experiments, isEmpty);
    });

    test('процесс: события и дни с событиями', () {
      final c = make();
      final p = c.addProcess(title: 'Чтение', dimensions: [LifeDimension.mind])!;
      c.addEvent(title: 'Глава', dimensions: [LifeDimension.mind], processIds: [p], at: DateTime(2026, 11, 16, 9), cost: const ResourceCost(minutes: 30));
      c.addEvent(title: 'Глава', dimensions: [LifeDimension.mind], processIds: [p], at: DateTime(2026, 11, 16, 21));
      final id = c.addExperiment(title: 'Читаю утром', metric: ExperimentMetric.process, processId: p, startedAt: DateTime(2026, 11, 15), days: 7)!;
      final r = c.experimentResultOf(c.experimentById(id)!);
      expect(r.after!.events!.events, 2);
      expect(r.after!.daysWithEvents, 1);
      expect(r.after!.events!.minutesKnown, 1);
      expect(r.before.events!.events, 0);
    });

    test('хранится в SQLite и в копии; битая запись в строгом импорте отвергается', () async {
      final db = await SqliteAppRepository.openDb(databaseFactoryFfi, inMemoryDatabasePath);
      addTearDown(db.close);
      final c = make(repo: SqliteAppRepository(opener: () async => db));
      await c.load();
      final id = c.addExperiment(title: 'Без сахара', metric: ExperimentMetric.weight, startedAt: DateTime(2026, 11, 1), days: 30)!;
      c.updateExperimentText(id, conclusion: 'вывод');
      await c.flush();
      final c2 = make(repo: SqliteAppRepository(opener: () async => db));
      await c2.load();
      expect(jsonEncode(c2.experimentById(id)!.toJson()), jsonEncode(c.experimentById(id)!.toJson()));
      final j = jsonDecode(c.exportBackup()) as Map<String, dynamic>;
      expect(j['schemaVersion'], greaterThanOrEqualTo(15));
      expect(() => AppData.fromJson({...j, 'experiments': [{'id': 'x'}]}, strict: true), throwsFormatException);
    });
  });

  testWidgets('создание эксперимента из «Разума» на узком экране', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(MemoryAppRepository(), saveDelay: Duration.zero);
    await c.load();
    await tester.pumpWidget(LifeOSApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab_mind')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('open_experiments')));
    await tester.tap(find.byKey(const ValueKey('open_experiments')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add_experiment')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('exp_title')), 'Без кофе после обеда');
    await tester.tap(find.byKey(const ValueKey('metric_steps')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('exp_save')));
    await tester.tap(find.byKey(const ValueKey('exp_save')));
    await tester.pumpAndSettle();
    final x = c.experiments.single;
    expect(x.metric, ExperimentMetric.steps);
    await tester.tap(find.byKey(ValueKey('exp_${x.id}')));
    await tester.pumpAndSettle();
    expect(find.text('медиана по дням'), findsWidgets);
    expect(tester.takeException(), isNull);
    // идущий эксперимент виден на «Сегодня»
    Navigator.of(tester.element(find.text('медиана по дням').first)).popUntil((r) => r.isFirst);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab_today')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('hub_exp_${x.id}')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
