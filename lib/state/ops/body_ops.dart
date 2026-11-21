part of '../app_controller.dart';

/// Тело: подходы, восстановление, вес, рост и цель по весу.
/// Расширение того же library: работает с состоянием контроллера напрямую, мутации — только через `_commit`.
extension BodyOps on AppController {
  // ---------------- тело ----------------

  /// Прогрессия 1RM по мышце: базовая история (до журнала) + лучший результат за каждый тренировочный день.
  /// Последние 8 точек.
  List<double> progression(String muscleId) {
    final m = _d.muscles[muscleId];
    final fromJournal = progressionFromSets(_d.workoutSets.where((s) => s.muscleId == muscleId));
    final all = [...?m?.history1RM.where((v) => v > 0), ...fromJournal];
    if (all.isEmpty) return [0];
    return all.length > 8 ? all.sublist(all.length - 8) : all;
  }

  /// Последний записанный подход по мышце (для подстановки веса/повторов в форму).
  WorkoutSet? lastSetFor(String muscleId) {
    for (int i = _d.workoutSets.length - 1; i >= 0; i--) {
      if (_d.workoutSets[i].muscleId == muscleId) return _d.workoutSets[i];
    }
    return null;
  }

  /// Записывает подход в журнал. [daysAgo] — задним числом (0 = сейчас).
  LogResult logWorkout(String muscleId, double weight, int reps, {int daysAgo = 0}) {
    final m = _d.muscles[muscleId];
    if (m == null || weight <= 0 || reps <= 0 || daysAgo < 0 || setsFull) return LogResult.rejected;

    final at = _clock().subtract(Duration(days: daysAgo));
    final set = WorkoutSet(
      id: 'set_${_clock().microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}',
      muscleId: muscleId,
      at: at,
      weight: weight,
      reps: reps,
    );
    final isRecord = set.estimated1RM > m.maxWeight + 1e-9;
    _commit(() => _insertSet(set));
    return LogResult(ok: true, isRecord: isRecord, oneRm: set.estimated1RM);
  }

  /// Удаляет подход. Возвращает удалённую запись (для «Отменить») или null.
  WorkoutSet? deleteSet(String id) {
    final i = _d.workoutSets.indexWhere((s) => s.id == id);
    if (i < 0) return null;
    late WorkoutSet removed;
    _commit(() {
      removed = _d.workoutSets.removeAt(i);
      _pending.deleteSet(removed.id);
      _recomputeMuscle(removed.muscleId);
    });
    return removed;
  }

  /// Возвращает ранее удалённый подход (кнопка «Отменить»).
  void restoreSet(WorkoutSet s) {
    if (setsFull || _d.muscles[s.muscleId] == null || _d.workoutSets.any((x) => x.id == s.id)) return;
    _commit(() => _insertSet(s));
  }

  /// Журнал подходов заполнен: новые не принимаются, старые не вытесняются.
  bool get setsFull => _d.workoutSets.length >= _maxSets;

  void _insertSet(WorkoutSet s) {
    assert(!setsFull, 'журнал подходов заполнен');
    _d.workoutSets.add(s);
    _d.workoutSets.sort((a, b) => a.at.compareTo(b.at));
    _pending.upsertSet(s);
    _recomputeMuscle(s.muscleId);
  }

  /// Производные поля мышцы = базовое состояние + журнал. Одна функция для добавления и удаления —
  /// поэтому состояние всегда согласовано.
  void _recomputeMuscle(String id) {
    final m = _d.muscles[id];
    if (m == null) return;
    final own = _d.workoutSets.where((s) => s.muscleId == id).toList(); // по возрастанию времени
    double best = m.baseMax;
    for (final s in own) {
      best = max(best, s.estimated1RM);
    }
    m.maxWeight = best;

    final base = m.baseTrainedAt;
    final last = own.isEmpty ? null : own.last.at;
    m.lastTrainedAt = (base != null && last != null) ? (base.isAfter(last) ? base : last) : (last ?? base);

    m.lastSets = [...own.reversed.take(6).map((s) => s.label), ...m.baseSets].take(6).toList();
  }

  void updateHealth({int? steps, int? calories, int? protein}) => _commit(() {
        if (steps != null) _d.dailySteps = max(0, steps);
        if (calories != null) _d.activeCalories = max(0, calories);
        if (protein != null) _d.proteinGrams = max(0, protein);
        if (steps != null || calories != null) _touchToday(activitySource: 'manual');
      });

  // ---------------- тело: вес, рост, цель ----------------

  /// Замеры веса по возрастанию времени.
  List<WeightEntry> get weights => List.unmodifiable(_d.weights);
  WeightEntry? get latestWeightEntry => latestWeight(_d.weights);
  int? get heightCm => _d.heightCm;
  String? get bodyGoal => _d.bodyGoal;

  /// ИМТ по последнему замеру и росту; null — нет веса или роста.
  double? get bodyMassIndex => bmi(latestWeightEntry?.kg, _d.heightCm);

  /// Вес из Health Connect за день: один замер с источником «health» на день (обновляется новым значением
  /// источника). Ручные замеры не трогаются — видны оба.
  void _recordHealthWeight(DateTime day, double kg) {
    final key = dayKey(day);
    final i = _d.weights.indexWhere((w) => w.source == 'health' && dayKey(w.at) == key);
    final v = round1(kg);
    if (i >= 0 && _d.weights[i].kg == v) return;
    final at = i >= 0 ? _d.weights[i].at : DateTime(day.year, day.month, day.day, 8);
    final e = WeightEntry(id: i >= 0 ? _d.weights[i].id : 'w_hc_$key', at: at, kg: v, source: 'health');
    if (!e.isValid) return;
    if (i >= 0) {
      _d.weights[i] = e;
    } else {
      _d.weights
        ..add(e)
        ..sort((a, b) => a.at.compareTo(b.at));
    }
  }

  /// Записывает замер веса. [at] — когда взвешивались (не в будущем). Возвращает id или null.
  String? addWeight(double kg, {DateTime? at}) {
    final now = _clock();
    final when = at ?? now;
    if (when.isAfter(now.add(const Duration(minutes: 5))) || _d.weights.length >= kMaxSnapshots) return null;
    final e = WeightEntry(id: 'w_${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}', at: when, kg: round1(kg));
    if (!e.isValid) return null;
    _commit(() => _d.weights
      ..add(e)
      ..sort((a, b) => a.at.compareTo(b.at)));
    return e.id;
  }

  /// Удаляет ошибочный замер (явное действие). Возвращает удалённый — для «Отменить».
  WeightEntry? removeWeight(String id) {
    final i = _d.weights.indexWhere((w) => w.id == id);
    if (i < 0) return null;
    late WeightEntry removed;
    _commit(() => removed = _d.weights.removeAt(i));
    return removed;
  }

  void restoreWeight(WeightEntry e) {
    if (_d.weights.any((w) => w.id == e.id) || !e.isValid) return;
    _commit(() => _d.weights
      ..add(e)
      ..sort((a, b) => a.at.compareTo(b.at)));
  }

  /// Рост в см (50–272); null снимает.
  bool setHeight(int? cm) {
    if (cm != null && (cm < 50 || cm > 272)) return false;
    _commit(() => _d.heightCm = cm);
    return true;
  }

  /// Цель по весу; null снимает.
  bool setBodyGoal(String? goal) {
    if (goal != null && !BodyGoal.isValid(goal)) return false;
    _commit(() => _d.bodyGoal = goal);
    return true;
  }
}
