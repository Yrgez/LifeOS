part of '../app_controller.dart';

/// Журнал событий жизни, быстрая запись, обзор недели и «В этот день».
/// Расширение того же library: работает с состоянием контроллера напрямую, мутации — только через `_commit`.
extension EventOps on AppController {
  // ---------------- события жизни ----------------
  //
  // Журнал событий — ядро модели: факты BODY / MIND / MATERIAL с затратами ресурсов и связями с целями.
  // История не переписывается: правка = новая версия, отмена = пометка, удаление — только явное.

  /// Весь журнал: все версии, включая отменённые (для истории и проверки происхождения).
  List<LifeEvent> get allEvents => List.unmodifiable(_d.events);

  /// Актуальные события (последние версии, не отменённые), по возрастанию времени.
  List<LifeEvent> get events => _memo('events', () => List<LifeEvent>.unmodifiable(currentEvents(_d.events)));

  /// Поиск по всем записям: последние версии событий (отменённые — тоже, с пометкой), операции, отметки,
  /// процессы, цели, достижения, счета.
  List<SearchHit> search(String query) {
    final replaced = {for (final e in _d.events) if (e.supersedesId != null) e.supersedesId!};
    return searchRecords(
      query,
      events: [for (final e in _d.events) if (!replaced.contains(e.id)) e],
      transactions: _d.transactions,
      checkIns: checkInsByDay.values,
      processes: _d.processes,
      goals: _d.goals,
      achievements: _d.achievements,
      bills: _d.bills,
      tasks: _d.tasks,
    );
  }

  bool get eventsFull => _d.events.length >= _maxEvents;

  LifeEvent? eventById(String id) {
    for (final e in _d.events) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Версии события от первой к последней.
  List<LifeEvent> eventRevisions(String id) => revisionChain(_d.events, id);

  /// Актуальные события цели: связанные с ней напрямую или через процесс, который ей служит.
  List<LifeEvent> eventsForGoal(String goalId) => goalEvents(goalId, events, _d.processes);

  /// Что уже вложено в цель: ресурсы, число событий (напрямую / через процессы), затронутые измерения.
  GoalFact goalFactOf(String goalId) => _memo(('goalFact', goalId), () => goalFact(goalId, events, _d.processes));

  /// Распределение ресурсов за [days] дней, заканчивающихся сегодня: по измерениям, процессам, с прошлым периодом.
  ResourceBreakdown resourceBreakdownFor(int days) =>
      _memo(('resources', days), () => resourceBreakdown(current: events, transactions: _d.transactions, now: _clock(), days: days));

  /// Фиксирует событие. Возвращает id или null (неверные данные, событие в будущем, журнал полон).
  String? addEvent({
    required String title,
    required Iterable<String> dimensions,
    String kind = LifeEventKind.action,
    DateTime? at,
    String note = '',
    ResourceCost cost = ResourceCost.none,
    Iterable<String> goalIds = const [],
    Iterable<String> processIds = const [],
    Iterable<EventRef> refs = const [],
    String source = EventSource.manual,
  }) =>
      _appendEvent(
        title: title,
        dimensions: dimensions,
        kind: kind,
        at: at,
        note: note,
        cost: cost,
        goalIds: goalIds,
        processIds: processIds,
        refs: refs,
        source: source,
      );

  /// Новая версия события (прежняя остаётся в истории). Править можно только последнюю версию
  /// неотменённого события. Возвращает id новой версии или null.
  String? reviseEvent(
    String id, {
    required String title,
    required Iterable<String> dimensions,
    required String kind,
    required DateTime at,
    String note = '',
    ResourceCost cost = ResourceCost.none,
    Iterable<String> goalIds = const [],
    Iterable<String> processIds = const [],
    Iterable<EventRef>? refs,
  }) {
    final old = eventById(id);
    if (old == null || old.isVoided || latestRevision(_d.events, id)?.id != id) return null;
    return _appendEvent(
      title: title,
      dimensions: dimensions,
      kind: kind,
      at: at,
      note: note,
      cost: cost,
      goalIds: goalIds,
      processIds: processIds,
      refs: refs ?? old.refs,
      source: old.source,
      supersedesId: old.id,
    );
  }

  String? _appendEvent({
    required String title,
    required Iterable<String> dimensions,
    required String kind,
    DateTime? at,
    required String note,
    required ResourceCost cost,
    required Iterable<String> goalIds,
    required Iterable<String> processIds,
    required Iterable<EventRef> refs,
    required String source,
    String? supersedesId,
  }) {
    if (_d.events.length >= _maxEvents) {
      AppLog.e('Журнал событий достиг предела $_maxEvents — новое событие не принято');
      return null;
    }
    final now = _clock();
    final when = at ?? now;
    // событие — факт: будущее планируется целями, а не событиями (небольшой допуск на расхождение часов)
    if (when.isAfter(now.add(const Duration(minutes: 5)))) return null;
    final e = LifeEvent(
      id: 'ev_${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}',
      at: when,
      recordedAt: now,
      dimensions: dimensions.where(LifeDimension.isValid),
      kind: kind,
      title: title.trim(),
      note: note.trim(),
      cost: cost,
      goalIds: goalIds,
      processIds: processIds,
      refs: refs,
      source: source,
      supersedesId: supersedesId,
    );
    if (!e.isValid) return null;
    _commit(() {
      _d.events
        ..add(e)
        ..sort(compareEvents);
      _pending.upsertEvent(e);
    });
    return e.id;
  }

  /// Отменяет событие (оно остаётся в истории с отметкой). Отменяется последняя версия цепочки.
  bool voidEvent(String id) {
    final latest = latestRevision(_d.events, id);
    if (latest == null || latest.isVoided) return false;
    _replaceEvent(latest.copyWith(voidedAt: _clock()));
    return true;
  }

  /// Снимает отметку отмены (кнопка «Вернуть»).
  bool unvoidEvent(String id) {
    final latest = latestRevision(_d.events, id);
    if (latest == null || !latest.isVoided) return false;
    _replaceEvent(latest.copyWith(clearVoided: true));
    return true;
  }

  void _replaceEvent(LifeEvent e) {
    final i = _d.events.indexWhere((x) => x.id == e.id);
    if (i < 0) return;
    _commit(() {
      _d.events[i] = e;
      _pending.upsertEvent(e);
    });
  }

  /// Удаляет событие НАВСЕГДА вместе со всеми его версиями. Только по явному решению пользователя.
  /// Возвращает число удалённых записей.
  int purgeEvent(String id) {
    final chain = eventRevisions(id);
    if (chain.isEmpty) return 0;
    final ids = {for (final e in chain) e.id};
    _commit(() {
      _d.events.removeWhere((e) => ids.contains(e.id));
      ids.forEach(_pending.deleteEvent);
    });
    return ids.length;
  }

  // ---------------- быстрая запись ----------------

  /// Записывает такое же событие сейчас (те же измерения, вид, ресурсы, цели и процессы; ссылки на записи не копируются).
  String? repeatEvent(String id) {
    final e = latestRevision(_d.events, id);
    if (e == null || e.kind == LifeEventKind.review) return null;
    return addEvent(
      title: e.title,
      dimensions: e.dimensions,
      kind: e.kind,
      note: e.note,
      cost: e.cost,
      goalIds: e.goalIds,
      processIds: e.processIds,
    );
  }

  /// Подходы за день [day], на которые ещё не ссылается ни одно актуальное событие.
  List<WorkoutSet> unrecordedSets(DateTime day) => _memo(('unrecorded', dayKey(day)), () {
        final start = DateTime(day.year, day.month, day.day), end = DateTime(day.year, day.month, day.day + 1);
        final referenced = {for (final e in events) for (final r in e.refs) if (r.type == EventRef.workoutSet) r.id};
        // журнал отсортирован по времени: идём с конца и останавливаемся на предыдущем дне
        final out = <WorkoutSet>[];
        for (var i = _d.workoutSets.length - 1; i >= 0; i--) {
          final s = _d.workoutSets[i];
          if (s.at.isBefore(start)) break;
          if (s.at.isBefore(end) && !referenced.contains(s.id)) out.add(s);
        }
        return List<WorkoutSet>.unmodifiable(out.reversed);
      });

  /// Событие тренировки дня из подходов журнала: «Тренировка: Грудь, Бицепс», ссылки на подходы, источник — авто.
  /// Если событие тренировки этого дня уже есть — дополняется новой версией, а не дублируется.
  String? recordWorkoutEvent(DateTime day) {
    final fresh = unrecordedSets(day);
    if (fresh.isEmpty) return null;
    final key = dayKey(day);
    LifeEvent? existing;
    for (final e in events) {
      if (e.source == EventSource.auto && dayKey(e.at) == key && e.refs.any((r) => r.type == EventRef.workoutSet)) existing = e;
    }
    final setsById = {for (final s in _d.workoutSets) s.id: s};
    final ids = [...?existing?.refs.where((r) => r.type == EventRef.workoutSet).map((r) => r.id), ...fresh.map((s) => s.id)];
    final all = [for (final id in ids) if (setsById[id] != null) setsById[id]!];
    final names = <String>[];
    for (final s in all) {
      final n = _d.muscles[s.muscleId]?.name ?? s.muscleId;
      if (!names.contains(n)) names.add(n);
    }
    final volume = all.fold<double>(0, (a, s) => a + s.weight * s.reps);
    final title = 'Тренировка: ${names.join(', ')}';
    final note = 'Подходов: ${all.length} · объём ${volume.round()} кг (из журнала тренировок)';
    final refs = [for (final s in all) EventRef(EventRef.workoutSet, s.id)];
    if (existing != null) {
      return reviseEvent(existing.id,
          title: title, dimensions: existing.dimensions, kind: existing.kind, at: existing.at, note: note, cost: existing.cost,
          goalIds: existing.goalIds, processIds: existing.processIds, refs: refs);
    }
    final first = all.map((s) => s.at).reduce((a, b) => a.isBefore(b) ? a : b);
    return addEvent(title: title, dimensions: [LifeDimension.body], at: first, note: note, refs: refs, source: EventSource.auto);
  }

  /// Событие из денежной операции: материальное измерение, деньги расхода — в ресурсах, ссылка на операцию.
  String? eventFromTransaction(String txId) {
    MoneyTx? t;
    for (final x in _d.transactions) {
      if (x.id == txId) t = x;
    }
    if (t == null) return null;
    for (final e in events) {
      if (e.refs.any((r) => r.type == EventRef.transaction && r.id == txId)) return e.id; // уже есть
    }
    final cat = finCategory(t.categoryId);
    return addEvent(
      title: t.note.isNotEmpty ? t.note : (cat?.name ?? 'Операция'),
      dimensions: [LifeDimension.material],
      at: t.at,
      cost: t.isIncome ? ResourceCost.none : ResourceCost(money: t.amount),
      refs: [EventRef(EventRef.transaction, t.id)],
      source: EventSource.auto,
    );
  }

  // ---------------- обзор недели и «в этот день» ----------------

  /// Факты для обзора: 7 дней, открытые процессы, прошлый обзор.
  ReviewFacts get weekReviewFacts => reviewFacts(breakdown: resourceBreakdownFor(7), current: events, processes: _d.processes);

  /// Пора ли предложить обзор (прошлого нет или он старше недели).
  bool get weekReviewDue => reviewDue(events, _clock());

  /// С какого момента пора делать обзор: сейчас, если он уже назрел; иначе через [reviewEveryDays] дней после
  /// прошлого. null — обзоры пока не нужны (нет ни прошлого обзора, ни событий).
  DateTime? get nextReviewDueAt {
    final now = _clock();
    if (reviewDue(events, now)) return now;
    final last = lastReview(events);
    return last?.at.add(const Duration(days: reviewEveryDays));
  }

  /// Сохраняет обзор событием вида «обзор» и применяет решения по процессам (новый статус с пометкой).
  /// Возвращает id события или null (ни одного ответа и ни одного решения — сохранять нечего).
  String? saveWeekReview(List<String> answers, {Map<String, String> processDecisions = const {}}) {
    final note = composeReviewNote(answers);
    final changes = {
      for (final e in processDecisions.entries)
        if (processById(e.key) != null && ProcessStatus.isValid(e.value) && processById(e.key)!.status != e.value) e.key: e.value,
    };
    if (note.isEmpty && changes.isEmpty) return null;
    final b = resourceBreakdownFor(7);
    final last = b.to.subtract(const Duration(days: 1));
    final id = addEvent(
      title: 'Обзор недели ${b.from.day}.${b.from.month.toString().padLeft(2, '0')}–${last.day}.${last.month.toString().padLeft(2, '0')}',
      dimensions: LifeDimension.all,
      kind: LifeEventKind.review,
      note: note,
    );
    if (id == null) return null;
    for (final e in changes.entries) {
      setProcessStatus(e.key, e.value, note: 'по итогам обзора недели');
    }
    return id;
  }

  /// «В этот день»: год (или месяц) назад → сейчас, только факты. null — сравнивать не с чем.
  Memory? get memory => memoryFor(
        now: _clock(),
        weights: _d.weights,
        sets: _d.workoutSets,
        muscles: _d.muscles,
        snapshots: _d.snapshots,
        currentEvents: events,
        processes: _d.processes,
      );
}
