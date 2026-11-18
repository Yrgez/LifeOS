// Эксперимент: человек сам меняет что-то в жизни и смотрит, что стало с выбранным показателем.
// Чистый Dart, без Flutter.
//
// Период A — [days] дней до начала, период B — [days] дней с начала (или до досрочного завершения).
// Система показывает сырые значения обоих периодов и сколько дней с данными — без вердиктов «помогло».
// Дата начала и показатель после создания не меняются: иначе сравнение можно незаметно подогнать.

class ExperimentMetric {
  static const steps = 'steps';
  static const sleep = 'sleep';
  static const protein = 'protein';
  static const calories = 'kcal';
  static const weight = 'weight';
  static const energy = 'energy'; // оценки энергии в событиях
  static const process = 'process'; // события процесса
  static const dayRating = 'day'; // вечерняя оценка дня 1–5

  static const all = [dayRating, sleep, steps, weight, protein, calories, energy, process];
  static const labels = {
    steps: 'Шаги за день',
    sleep: 'Сон за ночь',
    protein: 'Белок за день',
    calories: 'Активные ккал за день',
    weight: 'Вес',
    energy: 'Энергия в событиях (1–5)',
    process: 'События процесса',
    dayRating: 'Оценка дня (1–5)',
  };

  /// Показатель — значение за день (можно смотреть распределение по дням).
  static bool isDaily(String m) => const {steps, sleep, protein, calories, weight}.contains(m);
}

class Experiment {
  static const maxText = 200;
  static const minDays = 3;
  static const maxDays = 90;

  final String id;
  String title; // что меняю
  String hypothesis; // чего жду — словами человека
  final String metric;
  final String? processId; // только для ExperimentMetric.process
  final DateTime startedAt; // полночь дня начала
  final int days;
  final DateTime createdAt;
  DateTime? endedAt; // досрочно завершён (день завершения входит в период B)
  String conclusion; // вывод человека — система его не пишет

  Experiment({
    required this.id,
    required this.title,
    this.hypothesis = '',
    required this.metric,
    this.processId,
    required DateTime startedAt,
    required this.days,
    required this.createdAt,
    this.endedAt,
    this.conclusion = '',
  }) : startedAt = DateTime(startedAt.year, startedAt.month, startedAt.day);

  bool get isValid =>
      id.trim().isNotEmpty &&
      title.trim().isNotEmpty &&
      title.length <= maxText &&
      hypothesis.length <= maxText &&
      conclusion.length <= 2000 &&
      ExperimentMetric.all.contains(metric) &&
      (metric == ExperimentMetric.process) == (processId != null && processId!.isNotEmpty) &&
      days >= minDays &&
      days <= maxDays &&
      (endedAt == null || !endedAt!.isBefore(startedAt));

  /// Конец периода B (не включительно): плановый или день досрочного завершения.
  DateTime get plannedEnd => DateTime(startedAt.year, startedAt.month, startedAt.day + days);
  DateTime get end {
    if (endedAt == null) return plannedEnd;
    final e = DateTime(endedAt!.year, endedAt!.month, endedAt!.day + 1);
    return e.isBefore(plannedEnd) ? e : plannedEnd;
  }

  DateTime get baselineStart => DateTime(startedAt.year, startedAt.month, startedAt.day - days);

  bool isFinished(DateTime now) => endedAt != null || !now.isBefore(plannedEnd);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (hypothesis.isNotEmpty) 'hyp': hypothesis,
        'metric': metric,
        if (processId != null) 'proc': processId,
        'start': startedAt.millisecondsSinceEpoch,
        'days': days,
        'ct': createdAt.millisecondsSinceEpoch,
        if (endedAt != null) 'end': endedAt!.millisecondsSinceEpoch,
        if (conclusion.isNotEmpty) 'concl': conclusion,
      };

  factory Experiment.fromJson(Map<String, dynamic> j) => tryFromJson(j) ?? (throw const FormatException('Experiment'));

  static Experiment? tryFromJson(Map<String, dynamic> j) {
    DateTime? t(Object? v) => v is num && v.isFinite && v == v.roundToDouble() ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    String? s(Object? v, {bool optional = false}) => v == null && optional ? '' : (v is String ? v : null);
    final id = s(j['id']), title = s(j['title']), hyp = s(j['hyp'], optional: true), metric = s(j['metric']);
    final concl = s(j['concl'], optional: true);
    final start = t(j['start']), ct = t(j['ct']);
    final days = j['days'];
    final proc = j['proc'];
    if (id == null || title == null || hyp == null || metric == null || concl == null || start == null || ct == null) return null;
    if (days is! num || days != days.roundToDouble()) return null;
    if (proc != null && proc is! String) return null;
    if (j['end'] != null && t(j['end']) == null) return null;
    final x = Experiment(
      id: id,
      title: title,
      hypothesis: hyp,
      metric: metric,
      processId: proc as String?,
      startedAt: start,
      days: days.toInt(),
      createdAt: ct,
      endedAt: t(j['end']),
      conclusion: concl,
    );
    // дата начала хранится полуночью: другое значение — запись подправлена вручную
    return x.isValid && x.startedAt.millisecondsSinceEpoch == start.millisecondsSinceEpoch ? x : null;
  }
}
