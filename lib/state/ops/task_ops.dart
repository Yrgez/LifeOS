part of '../app_controller.dart';

/// Задачи: намерения на день. Выполнение — обычное событие журнала со ссылкой на задачу.
/// Расширение того же library: работает с состоянием контроллера напрямую, мутации — только через `_commit`.
extension TaskOps on AppController {
  List<LifeTask> get tasks => List.unmodifiable(_d.tasks);

  LifeTask? taskById(String id) => _d.tasks.where((t) => t.id == id).firstOrNull;

  String get _todayKey => dayKey(_clock());

  /// Открытые задачи на сегодня, включая дни раньше (что не сделано и не перенесено) — раньше назначенные первыми.
  List<LifeTask> get tasksForToday {
    final today = _todayKey;
    final list = [for (final t in _d.tasks) if (t.isOpen && t.day != null && t.day!.compareTo(today) <= 0) t];
    list.sort((a, b) {
      final d = a.day!.compareTo(b.day!);
      return d != 0 ? d : a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  /// Открытые задачи на будущие дни, по дню.
  List<LifeTask> get tasksUpcoming {
    final today = _todayKey;
    return [for (final t in _d.tasks) if (t.isOpen && t.day != null && t.day!.compareTo(today) > 0) t]..sort((a, b) => a.day!.compareTo(b.day!));
  }

  /// Открытые задачи без даты — «когда-нибудь».
  List<LifeTask> get tasksSomeday => [for (final t in _d.tasks) if (t.isOpen && t.day == null) t];

  /// Выполненные за последние [days] дней, новые сверху.
  List<LifeTask> tasksDoneRecently({int days = 7}) {
    final from = _clock().subtract(Duration(days: days));
    final list = [for (final t in _d.tasks) if (t.doneChange != null && t.doneChange!.at.isAfter(from)) t];
    return list..sort((a, b) => b.doneChange!.at.compareTo(a.doneChange!.at));
  }

  /// Открытые задачи процесса или цели.
  List<LifeTask> openTasksFor({String? processId, String? goalId}) => [
        for (final t in _d.tasks)
          if (t.isOpen && ((processId != null && t.processId == processId) || (goalId != null && t.goalId == goalId))) t,
      ];

  bool _dayOk(DateTime? day) {
    if (day == null) return true;
    final today = _clock();
    return !DateTime(day.year, day.month, day.day).isBefore(DateTime(today.year, today.month, today.day));
  }

  /// Новая задача. Измерения по умолчанию — от процесса или цели. День — сегодня или позже, либо без даты.
  String? addTask({
    required String title,
    Iterable<String> dimensions = const [],
    DateTime? day,
    String? processId,
    String? goalId,
    int? minutes,
    String note = '',
  }) {
    if (_d.tasks.length >= kMaxTasks || !_dayOk(day)) return null;
    if (processId != null && processById(processId) == null) return null;
    if (goalId != null && !_d.goals.any((g) => g.id == goalId)) return null;
    final dims = dimensions.isNotEmpty
        ? dimensions
        : processId != null
            ? processById(processId)!.dimensions
            : goalId != null
                ? goalFactOf(goalId).dimensions
                : const <String>[];
    final now = _clock();
    final t = LifeTask(
      id: 'task_${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}',
      title: title.trim(),
      note: note.trim(),
      dimensions: dims,
      processId: processId,
      goalId: goalId,
      minutes: minutes,
      log: [TaskChange(at: now, step: TaskStep.created, day: day == null ? null : dayKey(day))],
    );
    if (!t.isValid) return null;
    _commit(() => _d.tasks.add(t));
    return t.id;
  }

  /// Описание задачи (название, заметка, измерения, связи, оценка времени). День — через [planTask].
  bool updateTask(String id, {required String title, required Iterable<String> dimensions, String note = '', String? processId, String? goalId, int? minutes}) {
    final t = taskById(id);
    if (t == null) return false;
    if (processId != null && processById(processId) == null) return false;
    final probe = LifeTask(
      id: t.id,
      title: title.trim(),
      note: note.trim(),
      dimensions: dimensions,
      processId: processId,
      goalId: goalId,
      minutes: minutes,
      log: t.log,
    );
    if (!probe.isValid) return false;
    _commit(() {
      t
        ..title = probe.title
        ..note = probe.note
        ..dimensions = probe.dimensions
        ..processId = processId
        ..goalId = goalId
        ..minutes = minutes;
    });
    return true;
  }

  /// Перенос: новый день (сегодня или позже) или без даты. Дописывается в историю задачи.
  bool planTask(String id, DateTime? day) {
    final t = taskById(id);
    if (t == null || !t.isOpen || !_dayOk(day) || t.log.length >= LifeTask.maxLog) return false;
    final key = day == null ? null : dayKey(day);
    if (t.day == key) return true;
    _commit(() => t.log.add(TaskChange(at: _clock(), step: TaskStep.planned, day: key)));
    return true;
  }

  /// «Сделано»: событие журнала (с измерениями, процессом и целью задачи и ссылкой на неё). Время не подставляется:
  /// оценка — не факт; его можно указать, поправив событие. Возвращает id события.
  String? completeTask(String id, {DateTime? at, ResourceCost cost = ResourceCost.none}) {
    final t = taskById(id);
    if (t == null || !t.isOpen || t.log.length >= LifeTask.maxLog) return null;
    final evId = addEvent(
      title: t.title,
      dimensions: t.dimensions,
      at: at,
      note: t.note,
      cost: cost,
      processIds: [if (t.processId != null && processById(t.processId!) != null) t.processId!],
      goalIds: [if (t.goalId != null && _d.goals.any((g) => g.id == t.goalId)) t.goalId!],
      refs: [EventRef(EventRef.task, t.id)],
    );
    if (evId == null) return null;
    _commit(() => t.log.add(TaskChange(at: _clock(), step: TaskStep.done, eventId: evId)));
    return evId;
  }

  /// Вернуть в работу: выполненную (её событие отменяется и остаётся в истории) или отменённую задачу.
  bool reopenTask(String id) {
    final t = taskById(id);
    if (t == null || t.isOpen || t.log.length >= LifeTask.maxLog) return false;
    final ev = t.doneChange?.eventId;
    if (ev != null) voidEvent(ev);
    _commit(() => t.log.add(TaskChange(at: _clock(), step: TaskStep.reopened)));
    return true;
  }

  /// Отменить задачу: решено не делать. Задача и её история остаются.
  bool cancelTask(String id) {
    final t = taskById(id);
    if (t == null || !t.isOpen || t.log.length >= LifeTask.maxLog) return false;
    _commit(() => t.log.add(TaskChange(at: _clock(), step: TaskStep.cancelled)));
    return true;
  }
}
