/// Реестр разделов, которые можно скрыть. Чистая логика без Flutter.
///
/// Измерения (Тело, Разум, Материальное), события, процессы, цели и Хроника не скрываются — это ядро
/// концепции. Скрываются отдельные блоки, которые нужны не всем. Скрытие меняет только вид:
/// данные остаются, попадают в Хронику, экспорт и копию, Health Connect продолжает синхронизироваться.

class AppSection {
  final String id;
  final String title;
  final String where; // где находится — чтобы было понятно, что пропадёт
  const AppSection(this.id, this.title, this.where);
}

class Sections {
  static const weight = 'weight';
  static const workouts = 'workouts';
  static const steps = 'steps';
  static const salary = 'salary';
  static const graph = 'graph';
  static const experiments = 'experiments';
  static const checkIn = 'checkin';
  static const memory = 'memory';
  static const review = 'review';

  static const all = [
    AppSection(workouts, 'Тренировки', 'Тело: карта мышц, журнал подходов, сравнение метрик; «Сегодня»: восстановление'),
    AppSection(weight, 'Вес и ИМТ', 'Тело: вес, ИМТ, цель по весу'),
    AppSection(steps, 'Шаги и активность', '«Сегодня»: плитка шагов'),
    AppSection(checkIn, 'Отметка дня', '«Сегодня»: вечерний вопрос «Как прошёл день?»'),
    AppSection(review, 'Обзор недели', '«Сегодня»: напоминание раз в 7 дней'),
    AppSection(memory, '«В этот день»', '«Сегодня»: что было год или месяц назад'),
    AppSection(experiments, 'Эксперименты', 'Разум и «Сегодня»'),
    AppSection(graph, 'Граф связей', 'Разум'),
    AppSection(salary, 'Рост зарплаты', 'Материальное: график и точки зарплаты'),
  ];

  static final ids = {for (final s in all) s.id};
  static bool isValid(String id) => ids.contains(id);
}
