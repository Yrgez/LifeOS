import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app.dart';
import 'package:life_os/core/chronicle.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/sqlite_app_repository.dart';
import 'package:life_os/models/day_checkin.dart';
import 'package:life_os/models/experiment.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late DateTime now;
  AppController make([AppRepository? repo]) => AppController(repo ?? MemoryAppRepository(),
      clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n));
  setUp(() => now = DateTime(2026, 11, 18, 20));

  group('модель', () {
    test('проверка и JSON туда-обратно', () {
      final c = DayCheckIn(id: 'a', day: '2026-11-18', rating: 4, tags: ['кофе'], note: 'ок', recordedAt: now);
      expect(c.isValid, isTrue);
      expect(jsonEncode(DayCheckIn.tryFromJson(c.toJson())!.toJson()), jsonEncode(c.toJson()));
      final j = c.toJson();
      expect(DayCheckIn.tryFromJson({...j, 'r': 6}), isNull);
      expect(DayCheckIn.tryFromJson({...j, 'r': 3.5}), isNull);
      expect(DayCheckIn.tryFromJson({...j, 'day': '2026-02-30'}), isNull);
      expect(DayCheckIn.tryFromJson({...j, 'tags': ['Кофе']}), isNull); // метки хранятся нормализованными
      expect(DayCheckIn.tryFromJson({...j, 'tags': ['a', 'a']}), isNull);
      expect(DayCheckIn.tryFromJson({'id': 'x', 'day': '2026-11-18', 'at': 1}), isNull); // пустая отметка
    });

    test('сводка: распределение без среднего, метки по частоте', () {
      final byDay = {
        '2026-11-16': DayCheckIn(id: '1', day: '2026-11-16', rating: 4, tags: ['кофе'], recordedAt: now),
        '2026-11-17': DayCheckIn(id: '2', day: '2026-11-17', rating: 4, tags: ['кофе', 'бег'], recordedAt: now),
        '2026-11-18': DayCheckIn(id: '3', day: '2026-11-18', note: 'без оценки', recordedAt: now),
      };
      final s = summarizeCheckIns(byDay, ['2026-11-15', '2026-11-16', '2026-11-17', '2026-11-18']);
      expect((s.days, s.checked, s.rated), (4, 3, 2));
      expect(s.ratings, {4: 2});
      expect(s.tags.first, ('кофе', 2));
      expect(ratingDistribution({5: 1, 3: 2}), '5 — 1 дн., 3 — 2 дн.');
    });
  });

  group('контроллер', () {
    test('правка — новая версия; повтор без изменений версий не плодит', () {
      final c = make();
      final day = DateTime(2026, 11, 18);
      final v1 = c.setCheckIn(day, rating: 3)!;
      now = now.add(const Duration(minutes: 5));
      final v2 = c.setCheckIn(day, rating: 4, tags: [' Кофе ', 'кофе', 'Прогулка'], note: ' хорошо ')!;
      expect(v2, isNot(v1));
      expect(c.setCheckIn(day, rating: 4, tags: ['кофе', 'прогулка'], note: 'хорошо'), v2);
      final cur = c.checkInFor(day)!;
      expect((cur.rating, cur.note, cur.supersedesId), (4, 'хорошо', v1));
      expect(cur.tags, ['кофе', 'прогулка']);
      expect(c.checkInVersions(day).length, 2);
      expect(c.checkInsByDay.length, 1);
    });

    test('день: не в будущем и не раньше недели назад; пустая отметка отвергается', () {
      final c = make();
      expect(c.setCheckIn(DateTime(2026, 11, 19), rating: 3), isNull);
      expect(c.setCheckIn(DateTime(2026, 11, 10), rating: 3), isNull);
      expect(c.setCheckIn(DateTime(2026, 11, 11), rating: 3), isNotNull);
      expect(c.setCheckIn(DateTime(2026, 11, 18)), isNull);
      expect(c.setCheckIn(DateTime(2026, 11, 18), rating: 0), isNull);
    });

    test('когда спрашивать: вечером о сегодня, утром о вчера — только тем, кто отмечает', () {
      final c = make();
      now = DateTime(2026, 11, 18, 17, 59);
      expect(c.checkInPromptDay, isNull);
      now = DateTime(2026, 11, 18, 18);
      expect(c.checkInPromptDay, DateTime(2026, 11, 18));
      c.setCheckIn(now, rating: 4);
      expect(c.checkInPromptDay, isNull);
      now = DateTime(2026, 11, 20, 9); // 19-е пропущено
      expect(c.checkInPromptDay, DateTime(2026, 11, 19));
      now = DateTime(2026, 11, 20, 13);
      expect(c.checkInPromptDay, isNull);

      final fresh = make();
      now = DateTime(2026, 11, 20, 9);
      expect(fresh.checkInPromptDay, isNull); // новичка утром не спрашиваем о вчера
    });

    test('подсказки меток, хроника, эксперимент, обзор, экспорт', () {
      final c = make();
      for (var i = 0; i < 7; i++) {
        c.setCheckIn(DateTime(2026, 11, 12 + i), rating: i < 3 ? 3 : 4, tags: i.isEven ? ['кофе'] : ['бег', 'кофе']);
      }
      expect(c.checkInTagSuggestions, ['кофе', 'бег']);

      final months = groupChronicle(c.chronicle, snapshots: c.snapshotsByDay, checkIns: c.checkInsByDay);
      expect(months.single.days.length, 7); // дни с отметкой — в хронике, даже без событий
      expect(months.single.days.first.checkIn!.rating, 4);

      final id = c.addExperiment(title: 'Без экрана', metric: ExperimentMetric.dayRating, startedAt: DateTime(2026, 11, 15), days: 3)!;
      final r = c.experimentResultOf(c.experimentById(id)!);
      expect(r.before.ratings, {3: 3});
      expect(r.after!.ratings, {4: 3});

      final week = c.checkInSummary(7);
      expect(week.checked, 7);
      expect(week.ratings, {3: 3, 4: 4});

      expect(c.exportCsv('checkins')!.trim().split('\n').length, 8);
      final md = c.exportChronicleMarkdown();
      expect(md, contains('**день 4 из 5 · кофе**'));
    });

    test('хранится в SQLite и в копии; битая отметка в строгом импорте отвергается', () async {
      final db = await SqliteAppRepository.openDb(databaseFactoryFfi, inMemoryDatabasePath);
      addTearDown(db.close);
      final c = make(SqliteAppRepository(opener: () async => db));
      await c.load();
      c.setCheckIn(now, rating: 5, note: 'отлично');
      now = now.add(const Duration(minutes: 1));
      c.setCheckIn(now, rating: 4, note: 'хорошо');
      await c.flush();
      final c2 = make(SqliteAppRepository(opener: () async => db));
      await c2.load();
      expect(c2.checkInFor(now)!.note, 'хорошо');
      expect(c2.checkInVersions(now).length, 2);
      final j = jsonDecode(c.exportBackup()) as Map<String, dynamic>;
      expect(j['schemaVersion'], greaterThanOrEqualTo(16));
      expect(() => AppData.fromJson({...j, 'checkins': [{'id': 'x', 'day': 'вчера', 'r': 3, 'at': 1}]}, strict: true), throwsFormatException);
    });
  });

  testWidgets('вечером на «Сегодня»: оценка в одно нажатие, затем метки и заметка (360 px)', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(MemoryAppRepository(), clock: () => now, saveDelay: Duration.zero);
    await c.load();
    await tester.pumpWidget(LifeOSApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('checkin_tile')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hub_rating_4')));
    await tester.pumpAndSettle();
    expect(c.checkInFor(now)!.rating, 4);
    expect(find.byKey(const ValueKey('checkin_tile')), findsNothing);
    expect(find.byKey(const ValueKey('checkin_done')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('checkin_done')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('checkin_new_tag')), 'Прогулка');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('checkin_note')), 'Тихий вечер');
    await tester.ensureVisible(find.byKey(const ValueKey('checkin_save')));
    await tester.tap(find.byKey(const ValueKey('checkin_save')));
    await tester.pumpAndSettle();
    final cur = c.checkInFor(now)!;
    expect((cur.rating, cur.note), (4, 'Тихий вечер'));
    expect(cur.tags, ['прогулка']);
    expect(c.checkInVersions(now).length, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
