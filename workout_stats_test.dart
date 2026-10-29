import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/workout_stats.dart';
import 'package:life_os/models/models.dart';

WorkoutSet ws(DateTime at, double w, int r, {String m = 'chest', String? id}) =>
    WorkoutSet(id: id ?? '${at.microsecondsSinceEpoch}_$w$r$m', muscleId: m, at: at, weight: w, reps: r);

void main() {
  // 24.10.2026 — суббота
  final now = DateTime(2026, 10, 24, 18);

  test('dailyStats группирует по дням, считает объём, подходы и лучший 1RM', () {
    final sets = [
      ws(DateTime(2026, 10, 23, 9), 100, 5), // 500, 1RM 112.5
      ws(DateTime(2026, 10, 23, 9, 30), 80, 10), // 800, 1RM 106.7
      ws(DateTime(2026, 10, 24, 9), 60, 10), // 600
    ];
    final d = dailyStats(sets);
    expect(d.length, 2);
    expect(d[0].volume, 1300);
    expect(d[0].sets, 2);
    expect(d[0].best1RM, 112.5);
    expect(d[1].volume, 600);
  });

  test('progressionFromSets: лучший 1RM за день, по возрастанию дат', () {
    final sets = [
      ws(DateTime(2026, 10, 24), 60, 10),
      ws(DateTime(2026, 10, 20), 100, 1),
      ws(DateTime(2026, 10, 20, 12), 90, 1),
    ];
    expect(progressionFromSets(sets), [100, 80]);
  });

  group('volumeLastDays', () {
    test('нули для пустых дней, последний элемент — сегодня', () {
      final sets = [ws(DateTime(2026, 10, 24, 8), 100, 5), ws(DateTime(2026, 10, 22), 50, 10), ws(DateTime(2026, 10, 1), 999, 9)];
      expect(volumeLastDays(sets, now, 7), [0, 0, 0, 0, 500, 0, 500]);
    });
    test('переход на зимнее время не сдвигает дни', () {
      final n = DateTime(2026, 11, 2, 12); // после перевода часов в США 1 ноября
      final sets = [ws(DateTime(2026, 11, 1, 0, 30), 10, 10)];
      expect(volumeLastDays(sets, n, 3), [0, 100, 0]);
    });
  });

  group('volumeLastWeeks', () {
    test('недели с понедельника: сб 24.10 → неделя с 19.10', () {
      final sets = [
        ws(DateTime(2026, 10, 19), 10, 10), // понедельник текущей недели
        ws(DateTime(2026, 10, 24), 10, 10), // суббота текущей
        ws(DateTime(2026, 10, 18), 20, 10), // воскресенье прошлой
        ws(DateTime(2026, 8, 1), 5, 10), // за пределами 8 недель
      ];
      final v = volumeLastWeeks(sets, now, 8);
      expect(v.length, 8);
      expect(v.last, 200);
      expect(v[6], 200);
      expect(v.sublist(0, 6).every((x) => x == 0), isTrue);
    });
    test('подписи недель', () {
      final l = weekLabels(now, 3);
      expect(l, ['05.10', '12.10', '19.10']);
    });
  });

  group('окна', () {
    final sets = [
      ws(DateTime(2026, 10, 24), 100, 5), // 500 — сегодня
      ws(DateTime(2026, 10, 18), 100, 5), // 500 — 6 дней назад (в окне 7)
      ws(DateTime(2026, 10, 17), 100, 5), // 500 — 7 дней назад (предыдущее окно)
      ws(DateTime(2026, 10, 10), 100, 5), // 500 — 14 дней назад (вне обоих)
    ];
    test('volumeInWindow текущее и предыдущее', () {
      expect(volumeInWindow(sets, now, 7), 1000);
      expect(volumeInWindow(sets, now, 7, offsetDays: 7), 500);
    });
    test('setsInWindow и trainingDaysInWindow', () {
      expect(setsInWindow(sets, now, 7), 2);
      expect(trainingDaysInWindow(sets, now, 28), 4);
    });
  });

  test('volumeByMuscle сортирует по убыванию', () {
    final sets = [ws(now, 10, 10, m: 'abs'), ws(now, 100, 10, m: 'chest'), ws(now, 50, 10, m: 'quads')];
    expect(volumeByMuscle(sets, now, 7).map((e) => e.key), ['chest', 'quads', 'abs']);
  });

  test('percentChange', () {
    expect(percentChange(150, 100), 50);
    expect(percentChange(50, 100), -50);
    expect(percentChange(10, 0), isNull);
  });

  test('mondayOf и dayIndex', () {
    expect(mondayOf(now), DateTime(2026, 10, 19));
    expect(dayIndex(DateTime(2026, 10, 25)) - dayIndex(DateTime(2026, 10, 24)), 1);
  });
}
