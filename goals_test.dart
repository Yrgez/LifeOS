import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/models/models.dart';
import 'package:life_os/state/app_controller.dart';

void main() {
  late DateTime now;
  late MemoryAppRepository repo;

  Future<AppController> make() async {
    repo = MemoryAppRepository();
    final c = AppController(repo, clock: () => now, saveDelay: Duration.zero);
    await c.load();
    return c;
  }

  setUp(() => now = DateTime(2026, 10, 24, 12));

  String newGoal(AppController c) {
    c.addGoal('Жим', '', []);
    return c.goals.last.id;
  }

  const bench150 = MetricLink(kind: MetricLink.oneRM, muscleId: 'chest', target: 150);

  group('чекпоинты, привязанные к метрикам', () {
    test('1RM: выполняется по журналу и откатывается при удалении подхода', () async {
      final c = await make();
      final id = newGoal(c);
      expect(c.addCheckpoint(id, '', link: bench150), isTrue);
      final cp = c.goals.last.checkpoints.single;
      expect(cp.isCompleted, isFalse); // рекорд 120 < 150

      c.logWorkout('chest', 200, 1);
      expect(cp.isCompleted, isTrue);

      c.deleteSet(c.sets.single.id);
      expect(cp.isCompleted, isFalse);
    });

    test('капитал и доход', () async {
      final c = await make();
      final id = newGoal(c);
      c.addCheckpoint(id, '', link: const MetricLink(kind: MetricLink.netWorth, target: 5000000));
      c.addCheckpoint(id, '', link: const MetricLink(kind: MetricLink.income, target: 500000));
      final cps = c.goals.last.checkpoints;
      expect(cps.map((e) => e.isCompleted), [false, false]);
      c.updateWealth(netWorth: 5000000, income: 520000);
      expect(cps.map((e) => e.isCompleted), [true, true]);
    });

    test('вручную переключить такой чекпоинт нельзя', () async {
      final c = await make();
      final id = newGoal(c);
      c.addCheckpoint(id, '', link: bench150);
      c.toggleCheckpoint(id, 0, true);
      expect(c.goals.last.checkpoints.single.isCompleted, isFalse);
    });

    test('название генерируется из метрики', () async {
      final c = await make();
      final id = newGoal(c);
      c.addCheckpoint(id, '', link: bench150);
      final t = c.goals.last.checkpoints.single.title;
      expect(t, contains('Грудные мышцы'));
      expect(t, contains('150'));
    });

    test('валидация: цель ≤ 0, неизвестная мышца, пустое ручное название', () async {
      final c = await make();
      final id = newGoal(c);
      expect(c.addCheckpoint(id, '', link: const MetricLink(kind: MetricLink.netWorth, target: 0)), isFalse);
      expect(c.addCheckpoint(id, '', link: const MetricLink(kind: MetricLink.oneRM, muscleId: 'нет', target: 10)), isFalse);
      expect(c.addCheckpoint(id, '   '), isFalse);
      expect(c.addCheckpoint('нет такой цели', 'x'), isFalse);
      expect(c.goals.last.checkpoints, isEmpty);
    });

    test('метрика мышцы, которой нет, не ломает пересчёт', () {
      final c = AppController(MemoryAppRepository(), clock: () => now);
      const link = MetricLink(kind: MetricLink.oneRM, muscleId: 'нет', target: 10);
      expect(c.metricValue(link), isNull);
    });
  });

  group('достижение за цель', () {
    test('выдаётся при автоматическом выполнении и снимается, если рекорд удалён', () async {
      final c = await make();
      final id = newGoal(c);
      c.addCheckpoint(id, '', link: bench150);
      final achId = 'goal_done_$id';

      c.logWorkout('chest', 200, 1);
      expect(c.achievements.where((a) => a.id == achId).length, 1);
      expect(c.goals.last.celebrated, isTrue);

      c.deleteSet(c.sets.single.id); // «опечатка» удалена → цель снова не выполнена
      expect(c.achievements.any((a) => a.id == achId), isFalse);
      expect(c.goals.last.celebrated, isFalse);
    });

    test('вручную удалённое достижение не возвращается само', () async {
      final c = await make();
      final id = newGoal(c);
      c.addCheckpoint(id, '', link: bench150);
      c.logWorkout('chest', 200, 1);
      c.removeAchievement('goal_done_$id');
      c.updateHealth(steps: 1); // любая правка запускает пересчёт
      c.logWorkout('chest', 210, 1);
      expect(c.achievements.any((a) => a.id == 'goal_done_$id'), isFalse);
    });

    test('цель без чекпоинтов не считается выполненной', () async {
      final c = await make();
      final id = newGoal(c);
      expect(c.achievements.any((a) => a.id == 'goal_done_$id'), isFalse);
    });
  });

  group('редактирование целей', () {
    test('updateGoal меняет название, категорию, срок (только дата)', () async {
      final c = await make();
      final id = newGoal(c);
      expect(c.updateGoal(id, title: ' Новый ', category: 'Спорт', deadline: DateTime(2026, 12, 31, 18, 45)), isTrue);
      final g = c.goals.last;
      expect(g.title, 'Новый');
      expect(g.category, 'Спорт');
      expect(g.deadline, DateTime(2026, 12, 31));
    });

    test('срок можно снять', () async {
      final c = await make();
      c.addGoal('Цель', '', [], deadline: DateTime(2027, 1, 1));
      expect(c.goals.last.deadline, DateTime(2027, 1, 1));
      c.updateGoal(c.goals.last.id, title: 'Цель', category: '', deadline: null);
      expect(c.goals.last.deadline, isNull);
    });

    test('пустое название и неизвестная цель отклоняются', () async {
      final c = await make();
      final id = newGoal(c);
      expect(c.updateGoal(id, title: '  ', category: ''), isFalse);
      expect(c.updateGoal('нет', title: 'x', category: ''), isFalse);
    });

    test('removeCheckpoint и границы индекса', () async {
      final c = await make();
      c.addGoal('Цель', '', ['a', 'b', 'c']);
      final id = c.goals.last.id;
      c.removeCheckpoint(id, 1);
      expect(c.goals.last.checkpoints.map((e) => e.title), ['a', 'c']);
      c.removeCheckpoint(id, 99);
      c.removeCheckpoint(id, -1);
      expect(c.goals.last.checkpoints.length, 2);
    });
  });

  group('сохранение целей', () {
    test('срок, привязка и флаг достижения переживают круг JSON', () {
      final d = AppData.defaults(now: now);
      d.goals.add(GlobalGoal(
        id: 'g9',
        title: 'T',
        category: 'C',
        deadline: DateTime(2026, 12, 31),
        celebrated: true,
        checkpoints: [GoalCheckpoint(title: 'x', isCompleted: true, link: bench150)],
      ));
      final back = AppData.fromJson(d.toJson()).goals.last;
      expect(back.deadline, DateTime(2026, 12, 31));
      expect(back.celebrated, isTrue);
      expect(back.checkpoints.single.link!.kind, MetricLink.oneRM);
      expect(back.checkpoints.single.link!.muscleId, 'chest');
      expect(back.checkpoints.single.link!.target, 150);
    });

    test('старое сохранение без новых полей читается', () {
      final done = GlobalGoal.fromJson({
        'id': 'a', 'title': 'T', 'category': 'C',
        'checkpoints': [{'title': 'x', 'isCompleted': true}],
      });
      expect(done.deadline, isNull);
      expect(done.celebrated, isTrue); // уже выполнена — достижение не дублируется
      final open = GlobalGoal.fromJson({
        'id': 'b', 'title': 'T', 'category': 'C',
        'checkpoints': [{'title': 'x'}],
      });
      expect(open.celebrated, isFalse);
      expect(open.checkpoints.single.link, isNull);
    });
  });
}
