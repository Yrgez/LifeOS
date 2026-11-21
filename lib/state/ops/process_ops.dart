part of '../app_controller.dart';

/// Процессы и эксперименты.
/// Расширение того же library: работает с состоянием контроллера напрямую, мутации — только через `_commit`.
extension ProcessOps on AppController {
  // ---------------- процессы ----------------
  //
  // Процесс — рамка для событий: всё вложенное в него считается по событиям с его id.
  // Смена статуса дописывается в журнал статусов процесса, прежние статусы сохраняются.

  List<LifeProcess> get processes => List.unmodifiable(_d.processes);

  LifeProcess? processById(String id) {
    for (final p in _d.processes) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Актуальные события процесса, по возрастанию времени.
  List<LifeEvent> eventsForProcess(String processId) =>
      _memo(('processEvents', processId), () => List<LifeEvent>.unmodifiable([for (final e in events) if (e.processIds.contains(processId)) e]));

  /// Ресурсы, вложенные в процесс за всё время, первое и последнее событие.
  ProcessActivity processActivityOf(String processId) => _memo(('processActivity', processId), () => processActivity(events, processId));

  /// Начинает процесс. [startedAt] — когда он фактически начался (можно задним числом, не в будущем).
  /// Возвращает id или null.
  String? addProcess({
    required String title,
    required Iterable<String> dimensions,
    String description = '',
    Iterable<String> goalIds = const [],
    DateTime? startedAt,
    int? defaultMinutes,
    ProcessRhythm? rhythm, // at не важен: ритм действует с начала процесса
  }) {
    if (_d.processes.length >= kMaxProcesses) return null;
    final now = _clock();
    final start = startedAt ?? now;
    if (start.isAfter(now.add(const Duration(minutes: 5)))) return null;
    final p = LifeProcess(
      id: 'proc_${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}',
      title: title.trim(),
      description: description.trim(),
      dimensions: dimensions.where(LifeDimension.isValid),
      goalIds: goalIds,
      defaultMinutes: defaultMinutes,
      createdAt: now,
      statusLog: [ProcessStatusChange(at: start, status: ProcessStatus.active)],
      rhythmLog: [if (rhythm != null && rhythm.isSet) ProcessRhythm(at: start, times: rhythm.times, period: rhythm.period)],
    );
    if (!p.isValid) return null;
    _commit(() => _d.processes.add(p));
    return p.id;
  }

  /// Задаёт ритм ([times] раз за [period]); 0 — снять. Запись дописывается в журнал ритма — прошлые периоды
  /// продолжают сверяться с прежним ритмом. Тот же ритм повторно не записывается.
  bool setProcessRhythm(String id, int times, {String period = RhythmPeriod.week}) {
    final p = processById(id);
    if (p == null) return false;
    final r = ProcessRhythm(at: _clock(), times: times, period: period);
    if (!r.isValid || p.rhythmLog.length >= LifeProcess.maxLog) return false;
    final cur = p.rhythm;
    if (cur == null ? !r.isSet : (cur.times == r.times && cur.period == r.period)) return true;
    // при смене периода прошлые сверки по старому периоду не пересчитываются — журнал хранит оба
    if (p.rhythmLog.isNotEmpty && r.at.isBefore(p.rhythmLog.last.at)) return false;
    _commit(() => p.rhythmLog.add(r));
    return true;
  }

  /// Ритм процесса за последние [count] периодов (текущий первым); пусто — процесса нет.
  List<RhythmSpan> rhythmOf(String processId, {int count = 8}) => _memo(('rhythm', processId, count), () {
        final p = processById(processId);
        return p == null ? const <RhythmSpan>[] : List<RhythmSpan>.unmodifiable(rhythmHistory(p, events, _clock(), count: count));
      });

  /// Меняет описание процесса (название, измерения, цели, обычная длительность). Статус — только через [setProcessStatus].
  bool updateProcess(String id, {required String title, required Iterable<String> dimensions, String description = '', Iterable<String> goalIds = const [], int? defaultMinutes}) {
    final p = processById(id);
    if (p == null) return false;
    final dims = LifeEvent.normalizeDimensions(dimensions.where(LifeDimension.isValid));
    final t = title.trim();
    final desc = description.trim();
    final goals = goalIds.toSet().toList();
    if (t.isEmpty || t.length > LifeProcess.maxTitle || desc.length > LifeProcess.maxDescription || dims.isEmpty || goals.length > LifeEvent.maxLinks) {
      return false;
    }
    _commit(() {
      p
        ..title = t
        ..description = desc
        ..dimensions = dims
        ..goalIds = goals
        ..defaultMinutes = defaultMinutes;
    });
    return true;
  }

  /// Новая запись в журнале статусов. Тот же статус повторно не пишется.
  bool setProcessStatus(String id, String status, {String note = ''}) {
    final p = processById(id);
    if (p == null || !ProcessStatus.isValid(status) || p.status == status) return false;
    if (p.statusLog.length >= LifeProcess.maxLog || note.length > ProcessStatusChange.maxNote) return false;
    final now = _clock();
    // часы могли уйти назад — журнал статусов всё равно остаётся упорядоченным
    final at = now.isBefore(p.statusLog.last.at) ? p.statusLog.last.at : now;
    _commit(() => p.statusLog.add(ProcessStatusChange(at: at, status: status, note: note.trim())));
    return true;
  }

  /// Удаляет процесс НАВСЕГДА (только явно). События остаются: в них сохраняется ссылка на удалённый процесс.
  bool removeProcess(String id) {
    final i = _d.processes.indexWhere((p) => p.id == id);
    if (i < 0) return false;
    _commit(() => _d.processes.removeAt(i));
    return true;
  }

  // ---------------- эксперименты ----------------

  /// Новые сверху; идущие — раньше завершённых.
  List<Experiment> get experiments {
    final now = _clock();
    return [..._d.experiments]..sort((a, b) {
        final f = (a.isFinished(now) ? 1 : 0) - (b.isFinished(now) ? 1 : 0);
        return f != 0 ? f : b.startedAt.compareTo(a.startedAt);
      });
  }

  Experiment? experimentById(String id) {
    for (final x in _d.experiments) {
      if (x.id == id) return x;
    }
    return null;
  }

  ExperimentResult experimentResultOf(Experiment x) =>
      experimentResult(x, snapshots: _d.snapshots, weights: _d.weights, currentEvents: events, now: _clock(), checkIns: checkInsByDay);

  /// Новый эксперимент. Начало — не раньше чем [Experiment.maxDays] дней назад (период «до» должен быть
  /// уже в журнале, а не придуман задним числом) и не позже чем через 30 дней. Возвращает id или null.
  String? addExperiment({
    required String title,
    String hypothesis = '',
    required String metric,
    String? processId,
    required DateTime startedAt,
    required int days,
  }) {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(startedAt.year, startedAt.month, startedAt.day);
    if (start.isBefore(DateTime(today.year, today.month, today.day - Experiment.maxDays)) ||
        start.isAfter(DateTime(today.year, today.month, today.day + 30))) {
      return null;
    }
    if (processId != null && processById(processId) == null) return null;
    final x = Experiment(
      id: 'exp_${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}',
      title: title.trim(),
      hypothesis: hypothesis.trim(),
      metric: metric,
      processId: metric == ExperimentMetric.process ? processId : null,
      startedAt: start,
      days: days,
      createdAt: now,
    );
    if (!x.isValid || _d.experiments.length >= 500) return null;
    _commit(() => _d.experiments.add(x));
    return x.id;
  }

  /// Формулировки можно уточнять; показатель и даты — нет (иначе сравнение подгоняется).
  bool updateExperimentText(String id, {String? title, String? hypothesis, String? conclusion}) {
    final x = experimentById(id);
    if (x == null) return false;
    final t = title?.trim() ?? x.title, h = hypothesis?.trim() ?? x.hypothesis, c = conclusion?.trim() ?? x.conclusion;
    if (t.isEmpty || t.length > Experiment.maxText || h.length > Experiment.maxText || c.length > 2000) return false;
    _commit(() {
      x.title = t;
      x.hypothesis = h;
      x.conclusion = c;
    });
    return true;
  }

  /// Досрочное завершение: период «после» заканчивается сегодняшним днём.
  bool endExperiment(String id) {
    final x = experimentById(id);
    final now = _clock();
    if (x == null || x.isFinished(now) || now.isBefore(x.startedAt)) return false;
    _commit(() => x.endedAt = now);
    return true;
  }

  /// Удаление — явное действие с подтверждением в интерфейсе.
  bool removeExperiment(String id) {
    final i = _d.experiments.indexWhere((x) => x.id == id);
    if (i < 0) return false;
    _commit(() => _d.experiments.removeAt(i));
    return true;
  }
}
