import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../core/app_log.dart';
import '../core/currency.dart';
import '../core/bills.dart';
import '../core/body_stats.dart';
import '../core/chronicle.dart';
import '../core/finance_categories.dart';
import '../core/finance_stats.dart';
import '../core/import_rules.dart';
import '../core/goal_stats.dart';
import '../core/life_events.dart';
import '../core/experiments.dart';
import '../core/memories.dart';
import '../core/open_export.dart';
import '../core/review.dart';
import '../core/rhythm.dart';
import '../core/search.dart';
import '../core/sections.dart';
import '../core/statement_import.dart';
import '../core/recovery_stats.dart';
import '../core/resource_stats.dart';
import '../core/utils.dart';
import '../core/workout_stats.dart';
import '../data/app_data.dart';
import '../data/app_repository.dart';
import '../data/change_set.dart';
import '../data/health_source.dart';
import '../models/bill.dart';
import '../models/body.dart';
import '../models/day_checkin.dart';
import '../models/day_snapshot.dart';
import '../models/experiment.dart';
import '../models/finance_rules.dart';
import '../models/statement_import.dart';
import '../models/life_event.dart';
import '../models/life_process.dart';
import '../models/models.dart';

part 'ops/bill_ops.dart';
part 'ops/body_ops.dart';
part 'ops/category_ops.dart';
part 'ops/checkin_ops.dart';
part 'ops/goal_ops.dart';
part 'ops/event_ops.dart';
part 'ops/process_ops.dart';
part 'ops/section_ops.dart';
part 'ops/finance_ops.dart';

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
    int maxEvents = kMaxLifeEvents,
    this.saveDelay = const Duration(milliseconds: 400),
  })  : _clock = clock ?? DateTime.now,
        _random = random ?? Random(),
        _health = health,
        _initialData = initialData ?? ((now) => AppData.defaults(now: now)),
        _maxSets = maxWorkoutSets,
        _maxTx = maxTransactions,
        _maxEvents = maxEvents;

  final AppRepository _repo;
  final DateTime Function() _clock;
  final Random _random;
  final HealthDataSource? _health;
  final InitialData _initialData;
  final int _maxSets;
  final int _maxTx;
  final int _maxEvents;

  /// Изменения журналов с последнего успешного сохранения (репозиторий применяет их точечно).
  ChangeSet _pending = ChangeSet();
  final Duration saveDelay;

  late AppData _d = _initialData(_clock());
  bool _loaded = false;
  bool _disposed = false;
  bool _loadFailed = false;
  bool _writesBlocked = false;
  bool _syncing = false;
  String? _healthMessage;
  Timer? _saveTimer;

  // ---------------- чтение ----------------

  /// false — данные не прочитаны (ошибка хранилища / схема новее). Пока false, запись отключена,
  /// чтобы не затереть сохранённое значениями по умолчанию.
  bool get loaded => _loaded;

  /// true — последняя попытка чтения хранилища провалилась (UI показывает предупреждение).
  bool get loadFailed => _loadFailed;

  /// Запрещает сохранение, если предварительная проверка целостности/миграции не завершилась.
  /// Снимается только созданием нового контроллера после успешного восстановления при запуске.
  void blockWrites(String reason) {
    _writesBlocked = true;
    _loadFailed = true;
    AppLog.e('Запись отключена: $reason');
    _notify();
  }

  /// Капитал: сумма последних остатков счетов; пока счетов нет — значение, указанное вручную.
  int get netWorth => _d.accounts.isEmpty ? _d.netWorth : _d.accounts.fold(0, (a, x) => a + x.latest.amount);

  /// true — капитал считается по счетам (у каждой цифры есть дата снимка).
  bool get netWorthFromAccounts => _d.accounts.isNotEmpty;

  /// Доход и расходы в месяц, указанные вручную, — это ПЛАН (ориентир), а не факт. Факт — журнал операций.
  int get monthlyIncome => _d.monthlyIncome;
  int get monthlyExpense => _d.monthlyExpense;

  /// Доход для автоматических чекпоинтов: последний полный месяц по журналу операций, если доходы в журнале есть;
  /// иначе — плановый (указанный вручную).
  int get incomeEvidence {
    if (!_d.transactions.any((t) => t.isIncome)) return _d.monthlyIncome;
    final prev = addMonths(_clock(), -1);
    return monthTotals(_d.transactions, prev.year, prev.month).income;
  }
  int get dailySteps => _d.dailySteps;
  int get activeCalories => _d.activeCalories;
  int get proteinGrams => _d.proteinGrams;
  Map<String, MuscleGroup> get muscles => _d.muscles;
  List<GlobalGoal> get goals => _d.goals;
  List<AchievementItem> get achievements => _d.achievements;
  List<SalaryStep> get salaryHistory => _d.salaryHistory;
  List<GraphNode> get graphNodes => _d.graphNodes;
  List<GraphEdge> get graphEdges => _d.graphEdges;
  /// Дневные снимки (по возрастанию дат). Дня без снимка нет в списке: данных за него нет.
  List<DaySnapshot> get snapshots => List.unmodifiable(_d.snapshots.values);
  DaySnapshot? snapshotFor(DateTime day) => _d.snapshots[dayKey(day)];

  Map<String, DaySnapshot> get snapshotsByDay => Map.unmodifiable(_d.snapshots);

  /// Хроника: события, смены статусов процессов и достижения — новые сверху.
  List<ChronicleEntry> get chronicle => chronicleEntries(currentEvents: events, processes: _d.processes, achievements: _d.achievements, goals: _d.goals);

  /// Снимки последних [n] дней, заканчивая сегодняшним; null — данных за день нет.
  List<DaySnapshot?> lastDaysSnapshots(int n) {
    final t = _clock();
    return [for (var i = n - 1; i >= 0; i--) _d.snapshots[dayKey(DateTime(t.year, t.month, t.day - i))]];
  }

  // Ряды за 7 дней для мини-графиков. На графике «нет данных» рисуется нулём;
  // сами снимки различают ноль и отсутствие данных.
  List<double> get stepsWeekHistory => [for (final x in lastDaysSnapshots(7)) (x?.steps ?? 0).toDouble()];
  List<double> get caloriesWeekHistory => [for (final x in lastDaysSnapshots(7)) (x?.activeCalories ?? 0).toDouble()];

  /// Число узлов графа по дням: пропущенный день повторяет последнее известное значение
  /// (узлы между днями не исчезают), до первого известного — текущее число.
  List<double> get graphEvolutionHistory {
    final days = lastDaysSnapshots(7);
    var last = days.firstWhere((x) => x?.graphNodes != null, orElse: () => null)?.graphNodes ?? _d.graphNodes.length;
    return [
      for (final x in days) (last = x?.graphNodes ?? last).toDouble(),
    ];
  }

  /// Журнал подходов (по возрастанию времени). Не изменять напрямую — только через методы контроллера.
  List<WorkoutSet> get sets => List.unmodifiable(_d.workoutSets);

  DateTime get now => _clock();

  // --- настройки и знакомство ---
  String get userName => _d.userName;
  int get stepsGoal => _d.stepsGoal;
  int get proteinGoal => _d.proteinGoal;
  bool get onboardingDone => _d.onboardingDone;

  /// Нет ни журнала, ни операций, ни целей, ни капитала — приложение «пустое».
  bool get isBlank => _d.workoutSets.isEmpty && _d.transactions.isEmpty && _d.goals.isEmpty && netWorth == 0;

  /// Денежные операции (по возрастанию времени). Менять только через методы контроллера.
  List<MoneyTx> get transactions => List.unmodifiable(_d.transactions);

  // --- Health Connect ---
  bool get healthSupported => _health?.isSupported ?? false;
  bool get healthEnabled => _d.healthEnabled;
  bool get healthSyncing => _syncing;
  String? get healthMessage => _healthMessage;
  DateTime? get lastHealthSync => _d.lastHealthSyncMs == null ? null : DateTime.fromMillisecondsSinceEpoch(_d.lastHealthSyncMs!);

  /// Восстановление мышц по типовой оценке: сколько групп восстановлено, какие ещё нет и сколько им осталось.
  /// Заменяет прежний единый процент «готовности тела» (среднее оценок с точностью до процента).
  RecoveryOverview get recovery => recoveryOverview(_d.muscles, _clock());

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
        return caloriesWeekHistory;
      case 'chest':
        return progression('chest');
      case 'quads':
        return progression('quads');
      case 'graph':
        return graphEvolutionHistory;
      default:
        return stepsWeekHistory;
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
      _loadFailed = _writesBlocked;
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

  /// Вызывается только после успешного явного удаления старого хранилища.
  /// С этого момента допустимо создать новую пустую базу и снова сохранять данные.
  Future<void> onStorageReset() async {
    _writesBlocked = false;
    _loadFailed = false;
    _loaded = false;
    _pending = ChangeSet();
    await load();
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
    if (!_loaded || _writesBlocked) return;
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
    if (_writesBlocked) return;
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
    // снимок прошедшего дня уже записан; пропущенные дни остаются без снимков — «нет данных»
    _d.dailySteps = 0;
    _d.activeCalories = 0;
    _d.proteinGrams = 0;
    _d.lastDay = dayKey(now);
  }

  /// Подписи «системных» узлов графа и снимок текущего дня всегда отражают реальные цифры.
  void _syncDerived() {
    currentCurrency = currencyByCode(_d.currency) ?? currencies.first;
    setCustomFinCategories([for (final x in _d.categories) customFinCategory(x.id, x.name, x.isIncome, x.icon)],
        archived: {for (final x in _d.categories) if (x.archivedAt != null) x.id});
    void set(String id, String label) {
      for (final n in _d.graphNodes) {
        if (n.id == id) n.label = label;
      }
    }

    set('n_salary', 'ЗП: ${_d.monthlyIncome ~/ 1000}к');
    set('n_capital', 'Капитал ${(netWorth / 1000000).toStringAsFixed(2)}М');
    set('n_protein', 'Белок: ${_d.proteinGrams} г');
    set('n_activity', 'Шаги: ${(_d.dailySteps / 1000).toStringAsFixed(1)}k');
    final chest = _d.muscles['chest'];
    if (chest != null) set('n_chest', 'Грудь (1RM ${chest.maxWeight.toInt()})');
    for (final n in _d.graphNodes) {
      final r = n.ref;
      final title = r == null ? null : refTitle(r);
      if (title != null) n.label = title; // сущность удалена — узел хранит последнее название
    }

    _touchToday();
    _syncGoals();
  }

  // ---------------- дневные снимки ----------------

  /// Записывает снимок, если он изменился ([before] — подпись до изменения; null — снимка не было).
  void _putSnapshot(DaySnapshot x, String? before) {
    if (before == x.signature) return;
    if (before == null && _d.snapshots.length >= kMaxSnapshots) {
      AppLog.e('Дневных снимков больше $kMaxSnapshots — новый день не записан');
      return;
    }
    _d.snapshots[x.day] = x;
    _pending.upsertSnapshot(x);
  }

  /// Снимок текущего дня = текущие значения. Нулевые шаги, калории и белок считаются «не введено»,
  /// пока за день не было ненулевого значения (после него ноль — это исправление пользователя).
  void _touchToday({String? activitySource}) {
    final key = dayKey(_clock());
    final existing = _d.snapshots[key];
    final x = existing ?? DaySnapshot(day: key);
    final before = existing?.signature;
    int? keep(int v, int? old) => v > 0 || old != null ? v : null;
    x
      ..steps = keep(_d.dailySteps, x.steps)
      ..activeCalories = keep(_d.activeCalories, x.activeCalories)
      ..protein = keep(_d.proteinGrams, x.protein)
      ..netWorth = netWorth
      ..graphNodes = _d.graphNodes.length;
    if (activitySource != null && (x.steps != null || x.activeCalories != null)) x.activitySource = activitySource;
    _putSnapshot(x, before);
  }

  /// Данные источника за прошедший день (Health Connect): дополняют снимок того дня.
  void _recordPastActivity(DateTime day, {int? steps, int? calories, int? sleep}) {
    if (steps == null && calories == null && sleep == null) return;
    final key = dayKey(day);
    final existing = _d.snapshots[key];
    final x = existing ?? DaySnapshot(day: key);
    final before = existing?.signature;
    if (steps != null) x.steps = steps;
    if (calories != null) x.activeCalories = calories;
    if (sleep != null) x.sleepMinutes = sleep;
    if (steps != null || calories != null) x.activitySource = 'health';
    _putSnapshot(x, before);
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
              at: _clock(),
              category: g.category,
              iconKey: 'verified',
            ),
          );
        }
        _logGoal(g, 'Цель достигнута');
      } else if (!g.isComplete && g.celebrated) {
        g.celebrated = false;
        _d.achievements.removeWhere((a) => a.id == achId);
        _logGoal(g, 'Цель снова не выполнена (изменились чекпоинты или метрика)');
      }
    }
  }

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
      // подпись связанного узла берётся из процесса или цели
      if (newLabel != null && !autoNodeIds.contains(id) && !_refExists(n.ref)) n.label = newLabel;
      if (category != null && category != n.category) {
        n.category = category;
        n.color = nodeColorFor(category);
      }
    });
    return true;
  }

  // ---------------- граф: связь с процессами и целями ----------------

  bool _refExists(NodeRef? r) => r != null && refTitle(r) != null;

  /// Название процесса или цели по ссылке; null — сущность удалена (узел хранит последнее название).
  String? refTitle(NodeRef r) => switch (r.type) {
        NodeRef.process => processById(r.id)?.title,
        _ => _goal(r.id)?.title,
      };

  /// Узел, уже связанный с этой сущностью (одна сущность — один узел).
  GraphNode? nodeForRef(NodeRef r) {
    for (final n in _d.graphNodes) {
      if (n.ref == r) return n;
    }
    return null;
  }

  /// Сфера графа по измерению: тело → «gym», материальное → «wealth», разум → «mind».
  String _categoryFor(NodeRef r) {
    final dims = r.type == NodeRef.process ? (processById(r.id)?.dimensions ?? const []) : goalFactOf(r.id).dimensions;
    if (dims.isEmpty) return 'mind';
    return switch (dims.first) { LifeDimension.body => 'gym', LifeDimension.material => 'wealth', _ => 'mind' };
  }

  /// Связывает узел с процессом или целью ([ref] = null снимает связь). Системные узлы не связываются.
  bool linkNode(String nodeId, NodeRef? ref) {
    final n = nodeById(nodeId);
    if (n == null || autoNodeIds.contains(nodeId)) return false;
    if (ref != null) {
      final title = refTitle(ref);
      final taken = nodeForRef(ref);
      if (title == null || (taken != null && taken.id != nodeId)) return false;
    }
    _commit(() => n.ref = ref); // подпись подставит _syncDerived
    return true;
  }

  /// Новый узел для процесса или цели. Возвращает id узла (существующего, если уже есть) или null.
  String? addNodeFor(NodeRef ref) {
    final existing = nodeForRef(ref);
    if (existing != null) return existing.id;
    final title = refTitle(ref);
    if (title == null || !addNode(title, _categoryFor(ref))) return null;
    final n = _d.graphNodes.last;
    _commit(() => n.ref = ref);
    return n.id;
  }

  /// Собирает граф из того, что уже есть в жизни: узел на каждый процесс (кроме прекращённых) и цель,
  /// связь «процесс → цель», если процесс указан для цели. Уже нарисованное не трогает, дубликатов не создаёт.
  ({int nodes, int edges}) graphFromEntities() {
    final before = _d.graphNodes.length;
    for (final p in _d.processes) {
      if (p.status != ProcessStatus.stopped) addNodeFor(NodeRef(NodeRef.process, p.id));
    }
    for (final g in _d.goals) {
      addNodeFor(NodeRef(NodeRef.goal, g.id));
    }
    var edges = 0;
    for (final p in _d.processes) {
      final from = nodeForRef(NodeRef(NodeRef.process, p.id));
      if (from == null) continue;
      for (final gid in p.goalIds) {
        final to = nodeForRef(NodeRef(NodeRef.goal, gid));
        if (to != null && addEdge(from.id, to.id, kind: EdgeKind.supports)) edges++;
      }
    }
    return (nodes: _d.graphNodes.length - before, edges: edges);
  }

  /// Чем подтверждается связь в журналах — для связей между процессами и целями. null — узлы не связаны
  /// с сущностями (связь нарисована человеком, данных о ней нет).
  String? edgeEvidence(GraphEdge e) {
    final a = nodeById(e.fromId)?.ref, b = nodeById(e.toId)?.ref;
    if (a == null || b == null) return null;
    bool touches(LifeEvent ev, NodeRef r) => r.type == NodeRef.process ? ev.processIds.contains(r.id) : ev.goalIds.contains(r.id);
    final both = events.where((ev) => ev.kind != LifeEventKind.review && touches(ev, a) && touches(ev, b)).length;
    final parts = <String>[];
    final p = a.type == NodeRef.process ? a : (b.type == NodeRef.process ? b : null);
    final g = a.type == NodeRef.goal ? a : (b.type == NodeRef.goal ? b : null);
    if (p != null && g != null && (processById(p.id)?.goalIds.contains(g.id) ?? false)) parts.add('процесс указан для этой цели');
    parts.add(both == 0 ? 'событий, связанных с обоими, нет' : 'событий, связанных с обоими: $both');
    return parts.join(' · ');
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
          if (idx < 6) {
            _recordPastActivity(d.day, steps: d.steps, calories: d.activeCalories, sleep: d.sleepMinutes);
          } else {
            if (d.steps != null) _d.dailySteps = d.steps!;
            if (d.activeCalories != null) _d.activeCalories = d.activeCalories!;
            final p = d.protein;
            if (p != null && p > 0) _d.proteinGrams = p;
            _touchToday(activitySource: 'health');
            if (d.sleepMinutes != null) _recordPastActivity(d.day, sleep: d.sleepMinutes);
          }
          if (d.weightKg != null) _recordHealthWeight(d.day, d.weightKg!);
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

  /// Код основной валюты (RUB, USD…).
  String get currency => _d.currency;

  /// Меняет обозначение валюты. Суммы НЕ пересчитываются: курс неизвестен, а выдумывать его нельзя.
  bool setCurrency(String code) {
    if (currencyByCode(code) == null) return false;
    _commit(() => _d.currency = code);
    return true;
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
      ..currency = _d.currency
      ..heightCm = _d.heightCm
      ..bodyGoal = _d.bodyGoal
      ..lastHealthSyncMs = _d.lastHealthSyncMs
      ..onboardingDone = true;
    _d = fresh;
  }

  // ---------------- резервная копия ----------------

  /// Открытый экспорт: CSV-таблица по [kind] (events, transactions, days, weights, sets) или null — нет такого набора.
  String? exportCsv(String kind) => switch (kind) {
        'events' => eventsCsv(_d.events,
            goalTitles: {for (final g in _d.goals) g.id: g.title}, processTitles: {for (final p in _d.processes) p.id: p.title}),
        'transactions' => transactionsCsv(_d.transactions),
        'days' => snapshotsCsv(_d.snapshots.values),
        'weights' => weightsCsv(_d.weights),
        'sets' => setsCsv(_d.workoutSets, _d.muscles),
        'checkins' => checkInsCsv(_d.checkIns),
        _ => null,
      };

  /// Хроника в Markdown — читается без приложения.
  String exportChronicleMarkdown() => chronicleMarkdown(
        userName: _d.userName,
        now: _clock(),
        entries: chronicle,
        snapshots: _d.snapshots,
        currentEvents: events,
        processes: _d.processes,
        checkIns: checkInsByDay,
      );

  String exportBackup() => const JsonEncoder.withIndent('  ').convert(_d.toJson());

  /// Заменяет ВСЕ данные. false — текст не является корректной копией (данные не тронуты).
  bool importBackup(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return false;
      final v = j['schemaVersion'];
      if (v is! int || v < 1 || v > kSchemaVersion) return false;
      _d = AppData.fromJson(j, now: _clock(), strict: true);
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
