import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../core/app_log.dart';
import '../core/finance_categories.dart';
import '../core/finance_stats.dart';
import '../core/utils.dart';
import '../core/workout_stats.dart';
import '../data/app_data.dart';
import '../data/app_repository.dart';
import '../data/change_set.dart';
import '../data/health_source.dart';
import '../models/models.dart';

/// Вся бизнес-логика и состояние. UI только читает геттеры и вызывает методы.
/// Не зависит от виджетов → полностью тестируется без устройства.
/// Фабрика данных для первого запуска (когда в хранилище ничего нет).
typedef InitialData = AppData Function(DateTime now);

class AppController extends ChangeNotifier {
  AppController(
    this._repo, {
    DateTime Function()? clock,
    Random? random,
    HealthDataSource? health,
    InitialData? initialData,
    int maxWorkoutSets = kMaxWorkoutSets,
    int maxTransactions = kMaxTransactions,
    this.saveDelay = const Duration(milliseconds: 400),
  })  : _clock = clock ?? DateTime.now,
        _random = random ?? Random(),
        _health = health,
        _initialData = initialData ?? ((now) => AppData.defaults(now: now)),
        _maxSets = maxWorkoutSets,
        _maxTx = maxTransactions;

  final AppRepository _repo;
  final DateTime Function() _clock;
  final Random _random;
  final HealthDataSource? _health;
  final InitialData _initialData;
  final int _maxSets;
  final int _maxTx;

  /// Изменения журналов с последнего успешного сохранения (репозиторий применяет их точечно).
  ChangeSet _pending = ChangeSet();
  final Duration saveDelay;

  late AppData _d = _initialData(_clock());
  bool _loaded = false;
  bool _disposed = false;
  bool _loadFailed = false;
  bool _syncing = false;
  String? _healthMessage;
  Timer? _saveTimer;

  // ---------------- чтение ----------------

  /// false — данные не прочитаны (ошибка хранилища / схема новее). Пока false, запись отключена,
  /// чтобы не затереть сохранённое значениями по умолчанию.
  bool get loaded => _loaded;

  /// true — последняя попытка чтения хранилища провалилась (UI показывает предупреждение).
  bool get loadFailed => _loadFailed;

  int get netWorth => _d.netWorth;
  int get monthlyIncome => _d.monthlyIncome;
  int get monthlyExpense => _d.monthlyExpense;
  int get dailySteps => _d.dailySteps;
  int get activeCalories => _d.activeCalories;
  int get proteinGrams => _d.proteinGrams;
  Map<String, MuscleGroup> get muscles => _d.muscles;
  List<GlobalGoal> get goals => _d.goals;
  List<AchievementItem> get achievements => _d.achievements;
  List<SalaryStep> get salaryHistory => _d.salaryHistory;
  List<GraphNode> get graphNodes => _d.graphNodes;
  List<GraphEdge> get graphEdges => _d.graphEdges;
  List<double> get stepsWeekHistory => _d.stepsWeekHistory;
  List<double> get caloriesWeekHistory => _d.caloriesWeekHistory;
  List<double> get graphEvolutionHistory => _d.graphEvolutionHistory;

  /// Журнал подходов (по возрастанию времени). Не изменять напрямую — только через методы контроллера.
  List<WorkoutSet> get sets => List.unmodifiable(_d.workoutSets);

  DateTime get now => _clock();

  // --- настройки и знакомство ---
  String get userName => _d.userName;
  int get stepsGoal => _d.stepsGoal;
  int get proteinGoal => _d.proteinGoal;
  bool get onboardingDone => _d.onboardingDone;

  /// Нет ни журнала, ни операций, ни целей, ни капитала — приложение «пустое».
  bool get isBlank => _d.workoutSets.isEmpty && _d.transactions.isEmpty && _d.goals.isEmpty && _d.netWorth == 0;

  /// Денежные операции (по возрастанию времени). Менять только через методы контроллера.
  List<MoneyTx> get transactions => List.unmodifiable(_d.transactions);

  // --- Health Connect ---
  bool get healthSupported => _health?.isSupported ?? false;
  bool get healthEnabled => _d.healthEnabled;
  bool get healthSyncing => _syncing;
  String? get healthMessage => _healthMessage;
  DateTime? get lastHealthSync => _d.lastHealthSyncMs == null ? null : DateTime.fromMillisecondsSinceEpoch(_d.lastHealthSyncMs!);

  int get systemReadiness {
    if (_d.muscles.isEmpty) return 0;
    final now = _clock();
    final total = _d.muscles.values.fold(0.0, (acc, m) => acc + m.recoveryAt(now));
    return ((total / _d.muscles.length) * 100).round();
  }

  /// Подписи последних 7 дней, заканчивая сегодняшним.
  List<String> get weekLabels {
    final now = _clock();
    return List.generate(7, (i) => dayNames[now.subtract(Duration(days: 6 - i)).weekday - 1]);
  }

  GraphNode? nodeById(String? id) {
    if (id == null) return null;
    for (final n in _d.graphNodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  List<double> metricSeries(String key) {
    switch (key) {
      case 'calories':
        return _d.caloriesWeekHistory;
      case 'chest':
        return progression('chest');
      case 'quads':
        return progression('quads');
      case 'graph':
        return _d.graphEvolutionHistory;
      default:
        return _d.stepsWeekHistory;
    }
  }

  // ---------------- жизненный цикл ----------------

  Future<void> load() async {
    try {
      final data = await _repo.load();
      if (data != null) {
        _d = data;
      } else {
        _pending.markFull(); // в хранилище ничего нет: стартовые данные пишем целиком
      }
      _loaded = true;
      _loadFailed = false;
    } catch (e, st) {
      _loadFailed = true;
      AppLog.e('Не удалось загрузить данные — запись отключена, чтобы не затереть сохранённое', e, st);
    }
    _rollOverDays();
    _generateRecurring();
    _syncDerived();
    _notify();
    if (_loaded) _scheduleSave();
    _autoSyncHealth();
  }

  /// Вызывать при возврате приложения на передний план: новый день, повторная попытка загрузки.
  Future<void> onResume() async {
    if (!_loaded) {
      await load();
      return;
    }
    _rollOverDays();
    _generateRecurring();
    _syncDerived();
    _notify();
    _scheduleSave();
    _autoSyncHealth();
  }

  /// Принудительно перерисовать подписчиков (например, раз в минуту — «восстановление» мышц зависит от времени).
  /// Периодический вызов UI (раз в минуту): «восстановление» мышц зависит от времени,
  /// а при смене суток нужно сдвинуть историю и создать наступившие повторяющиеся операции.
  void refresh() {
    if (_loaded && _d.lastDay != dayKey(_clock())) {
      _rollOverDays();
      _generateRecurring();
      _syncDerived();
      _scheduleSave();
    }
    _notify();
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    if (!_loaded) return;
    final changes = _pending;
    _pending = ChangeSet();
    try {
      await _repo.save(_d, changes: changes);
    } catch (e, st) {
      // Что именно не записалось — неизвестно, а параллельные записи могли уйти раньше: безопаснее
      // переписать журналы целиком при следующем сохранении.
      _pending.markFull();
      AppLog.e('Не удалось сохранить данные', e, st);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    unawaited(flush());
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () => unawaited(flush())); // дебаунс: серия правок = одна запись
  }

  /// Единая точка мутации: изменить → пересчитать производное → уведомить → сохранить.
  void _commit(void Function() fn) {
    fn();
    _syncDerived();
    _notify();
    _scheduleSave();
  }

  // ---------------- день / производные данные ----------------

  /// Новый день: сдвигаем недельные истории и обнуляем дневные счётчики.
  void _rollOverDays() {
    final now = _clock();
    final today = DateTime.utc(now.year, now.month, now.day);
    DateTime last;
    try {
      final p = _d.lastDay.split('-').map(int.parse).toList();
      last = DateTime.utc(p[0], p[1], p[2]);
    } catch (_) {
      _d.lastDay = dayKey(now);
      return;
    }
    final diff = today.difference(last).inDays;
    if (diff <= 0) return; // тот же день (или часы переведены назад) — ничего не трогаем
    for (int i = 0; i < min(diff, 7); i++) {
      push7(_d.stepsWeekHistory, 0);
      push7(_d.caloriesWeekHistory, 0);
      push7(_d.graphEvolutionHistory, _d.graphNodes.length.toDouble());
    }
    _d.dailySteps = 0;
    _d.activeCalories = 0;
    _d.proteinGrams = 0;
    _d.lastDay = dayKey(now);
  }

  /// Подписи «системных» узлов графа и последние точки историй всегда отражают реальные цифры.
  void _syncDerived() {
    void set(String id, String label) {
      for (final n in _d.graphNodes) {
        if (n.id == id) n.label = label;
      }
    }

    set('n_salary', 'ЗП: ${_d.monthlyIncome ~/ 1000}к');
    set('n_capital', 'Капитал ${(_d.netWorth / 1000000).toStringAsFixed(2)}М');
    set('n_protein', 'Белок: ${_d.proteinGrams} г');
    set('n_activity', 'Шаги: ${(_d.dailySteps / 1000).toStringAsFixed(1)}k');
    final chest = _d.muscles['chest'];
    if (chest != null) set('n_chest', 'Грудь (1RM ${chest.maxWeight.toInt()})');

    if (_d.graphEvolutionHistory.isNotEmpty) {
      _d.graphEvolutionHistory[_d.graphEvolutionHistory.length - 1] = _d.graphNodes.length.toDouble();
    }
    if (_d.stepsWeekHistory.isNotEmpty) _d.stepsWeekHistory[_d.stepsWeekHistory.length - 1] = _d.dailySteps.toDouble();
    if (_d.caloriesWeekHistory.isNotEmpty) _d.caloriesWeekHistory[_d.caloriesWeekHistory.length - 1] = _d.activeCalories.toDouble();

    _syncGoals();
  }

  /// Чекпоинты, привязанные к метрикам, выполняются автоматически; достижение за цель выдаётся один раз
  /// и снимается, если цель перестала быть выполненной (например, удалён ошибочный рекорд).
  void _syncGoals() {
    for (final g in _d.goals) {
      for (final cp in g.checkpoints) {
        final link = cp.link;
        if (link == null) continue;
        final v = metricValue(link);
        if (v != null) cp.isCompleted = v >= link.target;
      }
      final achId = 'goal_done_${g.id}';
      if (g.isComplete && !g.celebrated) {
        g.celebrated = true;
        if (!_d.achievements.any((a) => a.id == achId)) {
          _d.achievements.insert(
            0,
            AchievementItem(
              id: achId,
              title: 'Достигнута цель: ${g.title}',
              date: monthYear(_clock()),
              category: g.category,
              iconKey: 'verified',
            ),
          );
        }
      } else if (!g.isComplete && g.celebrated) {
        g.celebrated = false;
        _d.achievements.removeWhere((a) => a.id == achId);
      }
    }
  }

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
    if (m == null || weight <= 0 || reps <= 0 || daysAgo < 0) return LogResult.rejected;

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
    if (_d.muscles[s.muscleId] == null || _d.workoutSets.any((x) => x.id == s.id)) return;
    _commit(() => _insertSet(s));
  }

  void _insertSet(WorkoutSet s) {
    _d.workoutSets.add(s);
    _d.workoutSets.sort((a, b) => a.at.compareTo(b.at));
    _pending.upsertSet(s);
    if (_d.workoutSets.length > _maxSets) {
      final drop = _d.workoutSets.length - _maxSets;
      final dropped = _d.workoutSets.take(drop).toList();
      final affected = dropped.map((x) => x.muscleId).toSet();
      _d.workoutSets.removeRange(0, drop);
      for (final x in dropped) {
        _pending.deleteSet(x.id);
      }
      AppLog.e('Журнал превысил $_maxSets записей — удалено старейших: $drop');
      for (final id in affected) {
        _recomputeMuscle(id);
      }
    }
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
      });

  // ---------------- граф ----------------

  /// Узлы, чьи подписи подставляются из данных (см. _syncDerived) — переименовать их нельзя.
  static const autoNodeIds = {'n_salary', 'n_capital', 'n_protein', 'n_activity', 'n_chest'};

  bool addNode(String title, String category) {
    final t = title.trim();
    if (t.isEmpty) return false;
    _commit(() {
      _d.graphNodes.add(GraphNode(
        id: 'node_${_clock().microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}',
        label: t,
        category: category,
        // небольшой разброс, чтобы новые узлы не слипались в одну точку
        position: Offset(0.5 + (_random.nextDouble() - 0.5) * 0.3, 0.5 + (_random.nextDouble() - 0.5) * 0.3),
        color: nodeColorFor(category),
      ));
    });
    return true;
  }

  bool addEdge(String a, String b, {String kind = EdgeKind.related, int weight = 1}) {
    if (a == b || nodeById(a) == null || nodeById(b) == null || !EdgeKind.isValid(kind)) return false;
    final exists = _d.graphEdges.any((e) => (e.fromId == a && e.toId == b) || (e.fromId == b && e.toId == a));
    if (exists) return false;
    _commit(() => _d.graphEdges.add(GraphEdge(a, b, kind: kind, weight: clampI(weight, 1, 3))));
    return true;
  }

  /// Меняет тип и/или силу связи. Направление (from→to) не меняется.
  bool updateEdge(String key, {String? kind, int? weight}) {
    final i = _d.graphEdges.indexWhere((e) => e.key == key);
    if (i < 0 || (kind != null && !EdgeKind.isValid(kind))) return false;
    _commit(() => _d.graphEdges[i] = _d.graphEdges[i].copyWith(kind: kind, weight: weight == null ? null : clampI(weight, 1, 3)));
    return true;
  }

  bool removeEdge(String key) {
    if (!_d.graphEdges.any((e) => e.key == key)) return false;
    _commit(() => _d.graphEdges.removeWhere((e) => e.key == key));
    return true;
  }

  /// Переименовать узел / сменить сферу (цвет следует за сферой). Подписи авто-узлов не меняются.
  bool updateNode(String id, {String? label, String? category}) {
    final n = nodeById(id);
    if (n == null) return false;
    final newLabel = label?.trim();
    if (newLabel != null && newLabel.isEmpty) return false;
    _commit(() {
      if (newLabel != null && !autoNodeIds.contains(id)) n.label = newLabel;
      if (category != null && category != n.category) {
        n.category = category;
        n.color = nodeColorFor(category);
      }
    });
    return true;
  }

  void deleteNode(String id) => _commit(() {
        _d.graphNodes.removeWhere((n) => n.id == id);
        _d.graphEdges.removeWhere((e) => e.fromId == id || e.toId == id);
      });

  /// Перетаскивание: без записи на диск на каждый кадр — вызывайте [endMove] по окончании жеста.
  void moveNode(String id, Offset fractionalPos) {
    final n = nodeById(id);
    if (n == null) return;
    n.position = Offset(clampD(fractionalPos.dx, 0.05, 0.95), clampD(fractionalPos.dy, 0.05, 0.95));
    _notify();
  }

  void endMove() => _scheduleSave();

  void autoLayoutRadial() {
    if (_d.graphNodes.isEmpty) return;
    _commit(() {
      final n = _d.graphNodes.length;
      for (int i = 0; i < n; i++) {
        final angle = (2 * pi * i) / n - pi / 2;
        _d.graphNodes[i].position = Offset(0.5 + cos(angle) * 0.36, 0.5 + sin(angle) * 0.36);
      }
    });
  }

  // ---------------- цели и достижения ----------------

  /// Текущее значение метрики для привязанных чекпоинтов; null — метрика недоступна (мышцы нет).
  double? metricValue(MetricLink link) {
    switch (link.kind) {
      case MetricLink.oneRM:
        return _d.muscles[link.muscleId]?.maxWeight;
      case MetricLink.netWorth:
        return _d.netWorth.toDouble();
      case MetricLink.income:
        return _d.monthlyIncome.toDouble();
      default:
        return null;
    }
  }

  String _linkTitle(MetricLink l) {
    switch (l.kind) {
      case MetricLink.oneRM:
        return '1RM «${_d.muscles[l.muscleId]?.name ?? l.muscleId}» ≥ ${trimNum(l.target)} кг';
      case MetricLink.netWorth:
        return 'Капитал ≥ ${fmtMoney(l.target.round())} ₽';
      default:
        return 'Доход ≥ ${fmtMoney(l.target.round())} ₽ / мес';
    }
  }

  GlobalGoal? _goal(String id) => _d.goals.where((g) => g.id == id).firstOrNull;

  void addGoal(String title, String category, List<String> checkpoints, {DateTime? deadline}) {
    final t = title.trim();
    if (t.isEmpty) return;
    _commit(() {
      _d.goals.add(GlobalGoal(
        id: 'goal_${_clock().microsecondsSinceEpoch}',
        title: t,
        category: category.trim().isEmpty ? 'Стратегия' : category.trim(),
        deadline: deadline == null ? null : dateOnly(deadline),
        checkpoints: [
          for (final c in checkpoints)
            if (c.trim().isNotEmpty) GoalCheckpoint(title: c.trim()),
        ],
      ));
    });
  }

  /// Изменить цель. [deadline] = null снимает срок.
  bool updateGoal(String goalId, {required String title, required String category, DateTime? deadline}) {
    final g = _goal(goalId);
    final t = title.trim();
    if (g == null || t.isEmpty) return false;
    _commit(() {
      g.title = t;
      g.category = category.trim().isEmpty ? 'Стратегия' : category.trim();
      g.deadline = deadline == null ? null : dateOnly(deadline);
    });
    return true;
  }

  void removeGoal(String goalId) => _commit(() => _d.goals.removeWhere((g) => g.id == goalId));

  /// Добавить чекпоинт. С [link] он будет выполняться автоматически; пустое название генерируется из метрики.
  bool addCheckpoint(String goalId, String title, {MetricLink? link}) {
    final g = _goal(goalId);
    if (g == null) return false;
    if (link != null) {
      if (link.target <= 0) return false;
      if (link.kind == MetricLink.oneRM && _d.muscles[link.muscleId] == null) return false;
    }
    final t = title.trim().isNotEmpty ? title.trim() : (link != null ? _linkTitle(link) : '');
    if (t.isEmpty) return false;
    _commit(() => g.checkpoints.add(GoalCheckpoint(title: t, link: link)));
    return true;
  }

  void removeCheckpoint(String goalId, int index) {
    final g = _goal(goalId);
    if (g == null || index < 0 || index >= g.checkpoints.length) return;
    _commit(() => g.checkpoints.removeAt(index));
  }

  /// Ручное переключение. Привязанные к метрике чекпоинты вручную не переключаются.
  void toggleCheckpoint(String goalId, int index, bool value) {
    final g = _goal(goalId);
    if (g == null || index < 0 || index >= g.checkpoints.length) return;
    final cp = g.checkpoints[index];
    if (cp.link != null) return;
    _commit(() => cp.isCompleted = value);
  }

  void addAchievement(String title, String category) {
    final t = title.trim();
    if (t.isEmpty) return;
    _commit(() {
      _d.achievements.insert(
        0,
        AchievementItem(
          id: 'ach_${_clock().microsecondsSinceEpoch}',
          title: t,
          date: monthYear(_clock()),
          category: category.trim().isEmpty ? 'Личный рекорд' : category.trim(),
        ),
      );
    });
  }

  void removeAchievement(String id) => _commit(() => _d.achievements.removeWhere((a) => a.id == id));

  // ---------------- финансы ----------------

  void updateWealth({int? netWorth, int? income, int? expense}) => _commit(() {
        if (netWorth != null) _d.netWorth = netWorth;
        if (income != null) _d.monthlyIncome = max(0, income);
        if (expense != null) _d.monthlyExpense = max(0, expense);
      });

  bool addSalaryStep(String year, String role, int salary) {
    if (year.trim().isEmpty || salary <= 0) return false;
    _commit(() => _d.salaryHistory.add(SalaryStep(year: year.trim(), role: role.trim(), salary: salary)));
    return true;
  }

  bool updateSalaryStep(int index, String year, String role, int salary) {
    if (index < 0 || index >= _d.salaryHistory.length || year.trim().isEmpty || salary <= 0) return false;
    _commit(() => _d.salaryHistory[index] = SalaryStep(year: year.trim(), role: role.trim(), salary: salary));
    return true;
  }

  /// Удаляет точку и возвращает её (для «Отменить»).
  SalaryStep? removeSalaryStep(int index) {
    if (index < 0 || index >= _d.salaryHistory.length) return null;
    late SalaryStep removed;
    _commit(() => removed = _d.salaryHistory.removeAt(index));
    return removed;
  }

  /// Возвращает точку на прежнее место.
  void insertSalaryStep(int index, SalaryStep step) {
    _commit(() => _d.salaryHistory.insert(clampI(index, 0, _d.salaryHistory.length), step));
  }

  // ---------------- финансы: операции ----------------

  /// Добавляет операцию. Тип (доход/расход) определяет категория. При [affectsNetWorth] чистый капитал
  /// меняется на сумму операции; удаление операции откатит ровно это изменение.
  bool addTransaction({
    required String categoryId,
    required int amount,
    DateTime? at,
    String note = '',
    bool affectsNetWorth = true,
  }) {
    final cat = finCategory(categoryId);
    if (cat == null || amount <= 0) return false;
    final tx = MoneyTx(
      id: 'tx_${_clock().microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}',
      at: at ?? _clock(),
      isIncome: cat.isIncome,
      amount: amount,
      categoryId: categoryId,
      note: note.trim(),
      affectsNetWorth: affectsNetWorth,
    );
    _commit(() => _insertTx(tx, applyNetWorth: true));
    return true;
  }

  /// Удаляет операцию и откатывает её влияние на капитал. Возвращает удалённую запись (для «Отменить»).
  MoneyTx? deleteTransaction(String id) {
    final i = _d.transactions.indexWhere((t) => t.id == id);
    if (i < 0) return null;
    late MoneyTx removed;
    _commit(() {
      removed = _d.transactions.removeAt(i);
      _pending.deleteTx(removed.id);
      if (removed.affectsNetWorth) _d.netWorth -= removed.signed;
    });
    return removed;
  }

  void restoreTransaction(MoneyTx tx) {
    if (_d.transactions.any((t) => t.id == tx.id)) return;
    _commit(() => _insertTx(tx, applyNetWorth: true));
  }

  /// Изменяет операцию. Влияние на капитал пересчитывается: старое откатывается, новое применяется.
  bool updateTransaction(
    String id, {
    required String categoryId,
    required int amount,
    required DateTime at,
    String note = '',
    required bool affectsNetWorth,
  }) {
    final i = _d.transactions.indexWhere((t) => t.id == id);
    final cat = finCategory(categoryId);
    if (i < 0 || cat == null || amount <= 0) return false;
    final old = _d.transactions[i];
    final updated = MoneyTx(
      id: old.id,
      at: at,
      isIncome: cat.isIncome,
      amount: amount,
      categoryId: categoryId,
      note: note.trim(),
      affectsNetWorth: affectsNetWorth,
      recurringId: old.recurringId,
    );
    _commit(() {
      if (old.affectsNetWorth) _d.netWorth -= old.signed;
      if (updated.affectsNetWorth) _d.netWorth += updated.signed;
      _d.transactions[i] = updated;
      _d.transactions.sort((a, b) => a.at.compareTo(b.at));
      _pending.upsertTx(updated);
    });
    return true;
  }

  // ---------------- бюджеты ----------------

  Map<String, int> get budgets => Map.unmodifiable(_d.budgets);

  /// Лимит расходов на месяц по категории; [limit] ≤ 0 снимает лимит. Только для категорий расходов.
  bool setBudget(String categoryId, int limit) {
    final cat = finCategory(categoryId);
    if (cat == null || cat.isIncome) return false;
    _commit(() {
      if (limit > 0) {
        _d.budgets[categoryId] = limit;
      } else {
        _d.budgets.remove(categoryId);
      }
    });
    return true;
  }

  // ---------------- повторяющиеся операции ----------------

  List<RecurringTx> get recurring => List.unmodifiable(_d.recurring);

  /// Создаёт правило. Операции создаются автоматически, начиная с ближайшей даты не раньше сегодняшнего дня.
  bool addRecurring({
    required String categoryId,
    required int amount,
    required int dayOfMonth,
    String note = '',
    bool affectsNetWorth = true,
  }) {
    if (finCategory(categoryId) == null || amount <= 0 || dayOfMonth < 1 || dayOfMonth > 31) return false;
    _commit(() {
      _d.recurring.add(RecurringTx(
        id: 'rec_${_clock().microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}',
        categoryId: categoryId,
        amount: amount,
        dayOfMonth: dayOfMonth,
        note: note.trim(),
        affectsNetWorth: affectsNetWorth,
        start: dateOnly(_clock()),
      ));
      _generateRecurring();
    });
    return true;
  }

  /// Изменяет правило. Новые значения действуют на ещё не созданные операции; уже созданные не меняются,
  /// обработанные месяцы повторно не создаются. Дата начала правила сохраняется.
  bool updateRecurring(
    String id, {
    required String categoryId,
    required int amount,
    required int dayOfMonth,
    String note = '',
    required bool affectsNetWorth,
  }) {
    final i = _d.recurring.indexWhere((r) => r.id == id);
    if (i < 0 || finCategory(categoryId) == null || amount <= 0 || dayOfMonth < 1 || dayOfMonth > 31) return false;
    final old = _d.recurring[i];
    _commit(() {
      _d.recurring[i] = RecurringTx(
        id: old.id,
        categoryId: categoryId,
        amount: amount,
        dayOfMonth: dayOfMonth,
        note: note.trim(),
        affectsNetWorth: affectsNetWorth,
        start: old.start,
        lastMonth: old.lastMonth,
      );
      _generateRecurring(); // новое число могло «наступить» уже сегодня
    });
    return true;
  }

  /// Удаляет правило; уже созданные им операции остаются.
  void removeRecurring(String id) => _commit(() => _d.recurring.removeWhere((r) => r.id == id));

  /// Создаёт наступившие операции по правилам. Идемпотентно: месяц, уже обработанный правилом
  /// (`lastMonth`), повторно не создаётся — даже если операцию потом удалили вручную.
  void _generateRecurring() {
    final today = dateOnly(_clock());
    final thisMonth = DateTime(today.year, today.month, 1);
    for (final r in _d.recurring) {
      final cat = finCategory(r.categoryId);
      if (cat == null) continue;
      var month = parseYm(r.lastMonth) == null ? DateTime(r.start.year, r.start.month, 1) : addMonths(parseYm(r.lastMonth)!, 1);
      int guard = 0;
      while (!month.isAfter(thisMonth) && guard++ < 60) {
        final due = DateTime(month.year, month.month, min(r.dayOfMonth, daysInMonth(month)));
        if (due.isAfter(today)) break; // срок ещё не наступил — вернёмся позже
        final id = 'rec_${r.id}_${ymKey(month)}';
        if (!due.isBefore(r.start) && !_d.transactions.any((t) => t.id == id)) {
          _insertTx(
            MoneyTx(
              id: id,
              at: DateTime(due.year, due.month, due.day, 9),
              isIncome: cat.isIncome,
              amount: r.amount,
              categoryId: r.categoryId,
              note: r.note,
              affectsNetWorth: r.affectsNetWorth,
              recurringId: r.id,
            ),
            applyNetWorth: true,
          );
        }
        r.lastMonth = ymKey(month);
        month = addMonths(month, 1);
      }
    }
  }

  void _insertTx(MoneyTx tx, {required bool applyNetWorth}) {
    _d.transactions.add(tx);
    _d.transactions.sort((a, b) => a.at.compareTo(b.at));
    _pending.upsertTx(tx);
    if (applyNetWorth && tx.affectsNetWorth) _d.netWorth += tx.signed;
    if (_d.transactions.length > _maxTx) {
      final drop = _d.transactions.length - _maxTx;
      final dropped = _d.transactions.take(drop).toList();
      _d.transactions.removeRange(0, drop); // капитал не трогаем: старые операции уже учтены в нём
      for (final x in dropped) {
        _pending.deleteTx(x.id);
      }
      AppLog.e('Список операций превысил $_maxTx — удалено старейших: $drop');
    }
  }

  // ---------------- здоровье: Health Connect ----------------

  /// Запрашивает разрешения и включает автосинхронизацию.
  Future<HealthSyncStatus> connectHealth() async {
    final h = _health;
    if (h == null || !h.isSupported) return HealthSyncStatus.unsupported;
    if (_syncing) return HealthSyncStatus.busy;
    try {
      final granted = await h.requestPermission();
      if (!granted) {
        _healthMessage = 'Доступ к Health Connect не выдан';
        _notify();
        return HealthSyncStatus.permissionDenied;
      }
    } catch (e, st) {
      AppLog.e('Health Connect: запрос разрешений не удался', e, st);
      _healthMessage = 'Не удалось открыть запрос разрешений. Проверьте, что Health Connect установлен';
      _notify();
      return HealthSyncStatus.failed;
    }
    _d.healthEnabled = true;
    return syncHealth();
  }

  /// Выключает автосинхронизацию (разрешение в системе остаётся; отозвать — в настройках Health Connect).
  void disconnectHealth() {
    _healthMessage = null;
    _commit(() => _d.healthEnabled = false);
  }

  /// Читает последние 7 дней из источника и обновляет шаги/калории (сегодня и историю).
  /// Белок источником не читается — он остаётся ручным вводом.
  Future<HealthSyncStatus> syncHealth() async {
    final h = _health;
    if (h == null || !h.isSupported) return HealthSyncStatus.unsupported;
    if (_syncing) return HealthSyncStatus.busy;
    _syncing = true;
    _healthMessage = null;
    _notify();
    try {
      if (!await h.hasPermission()) {
        _d.healthEnabled = false;
        _healthMessage = 'Нет доступа к Health Connect — подключите заново';
        _commit(() {});
        return HealthSyncStatus.permissionDenied;
      }
      final now = _clock();
      final today = dateOnly(now);
      final days = await h.readDays(DateTime(today.year, today.month, today.day - 6), today);

      _commit(() {
        _rollOverDays();
        for (final d in days) {
          final idx = 6 - (dayIndex(today) - dayIndex(d.day));
          if (idx < 0 || idx > 6) continue;
          if (d.steps != null) _d.stepsWeekHistory[idx] = d.steps!.toDouble();
          if (d.activeCalories != null) _d.caloriesWeekHistory[idx] = d.activeCalories!.toDouble();
          if (idx == 6) {
            if (d.steps != null) _d.dailySteps = d.steps!;
            if (d.activeCalories != null) _d.activeCalories = d.activeCalories!;
            final p = d.protein;
            if (p != null && p > 0) _d.proteinGrams = p;
          }
        }
        _d.lastHealthSyncMs = now.millisecondsSinceEpoch;
      });
      return HealthSyncStatus.ok;
    } catch (e, st) {
      AppLog.e('Health Connect: синхронизация не удалась', e, st);
      _healthMessage = 'Не удалось прочитать данные Health Connect';
      return HealthSyncStatus.failed;
    } finally {
      _syncing = false;
      _notify();
    }
  }

  /// Тихая синхронизация при запуске и возврате в приложение (не чаще раза в 2 минуты).
  void _autoSyncHealth() {
    if (!_d.healthEnabled || !healthSupported) return;
    final last = _d.lastHealthSyncMs;
    if (last != null && _clock().millisecondsSinceEpoch - last < 120000) return;
    unawaited(syncHealth());
  }

  // ---------------- настройки и знакомство ----------------

  static String _cleanName(String s) {
    final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length > 40 ? t.substring(0, 40).trim() : t;
  }

  /// Меняет настройки. false — значение недопустимо (ничего не изменено).
  bool updateSettings({String? userName, int? stepsGoal, int? proteinGoal}) {
    if (stepsGoal != null && (stepsGoal < 1 || stepsGoal > 100000)) return false;
    if (proteinGoal != null && (proteinGoal < 1 || proteinGoal > 1000)) return false;
    _commit(() {
      if (userName != null) _d.userName = _cleanName(userName);
      if (stepsGoal != null) _d.stepsGoal = stepsGoal;
      if (proteinGoal != null) _d.proteinGoal = proteinGoal;
    });
    return true;
  }

  /// Завершает знакомство. Необязательные значения применяются, только если заданы и допустимы.
  /// [demo] заменяет данные примерами (только для «пустого» приложения — иначе пользовательские данные не трогаются).
  void completeOnboarding({
    String userName = '',
    int? stepsGoal,
    int? proteinGoal,
    int? netWorth,
    int? income,
    int? expense,
    bool demo = false,
  }) {
    _commit(() {
      if (demo && isBlank) _replaceKeepingSettings(AppData.defaults(now: _clock()));
      _d.userName = _cleanName(userName);
      if (stepsGoal != null && stepsGoal >= 1 && stepsGoal <= 100000) _d.stepsGoal = stepsGoal;
      if (proteinGoal != null && proteinGoal >= 1 && proteinGoal <= 1000) _d.proteinGoal = proteinGoal;
      if (netWorth != null) _d.netWorth = netWorth;
      if (income != null && income >= 0) _d.monthlyIncome = income;
      if (expense != null && expense >= 0) _d.monthlyExpense = expense;
      _d.onboardingDone = true;
    });
  }

  /// Показать знакомство снова (данные не затрагиваются).
  void restartOnboarding() => _commit(() => _d.onboardingDone = false);

  /// Сбросить все данные: пустое состояние или примеры. Имя, цели дня и подключение Health Connect сохраняются.
  void resetAllData({bool demo = false}) {
    _commit(() => _replaceKeepingSettings(demo ? AppData.defaults(now: _clock()) : AppData.blank(now: _clock())));
  }

  void _replaceKeepingSettings(AppData fresh) {
    _pending.markFull();
    fresh
      ..userName = _d.userName
      ..stepsGoal = _d.stepsGoal
      ..proteinGoal = _d.proteinGoal
      ..healthEnabled = _d.healthEnabled
      ..lastHealthSyncMs = _d.lastHealthSyncMs
      ..onboardingDone = true;
    _d = fresh;
  }

  // ---------------- резервная копия ----------------

  String exportBackup() => const JsonEncoder.withIndent('  ').convert(_d.toJson());

  /// Заменяет ВСЕ данные. false — текст не является корректной копией (данные не тронуты).
  bool importBackup(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return false;
      final v = (j['schemaVersion'] as num?)?.toInt();
      if (v == null || v > kSchemaVersion) return false;
      _d = AppData.fromJson(j, now: _clock());
      _pending.markFull();
      _loaded = true; // пользователь явно задал данные — можно писать
    } catch (e, st) {
      AppLog.e('Импорт резервной копии не удался', e, st);
      return false;
    }
    _rollOverDays();
    _generateRecurring();
    _commit(() {});
    return true;
  }
}

/// Итог записи подхода.
class LogResult {
  final bool ok;
  final bool isRecord; // новый личный рекорд расчётного 1RM
  final double oneRm;
  const LogResult({required this.ok, required this.isRecord, required this.oneRm});
  static const rejected = LogResult(ok: false, isRecord: false, oneRm: 0);
}

enum HealthSyncStatus { ok, unsupported, permissionDenied, failed, busy }
