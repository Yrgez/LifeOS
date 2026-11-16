import 'dart:collection';

import '../core/app_log.dart';
import '../core/currency.dart';
import '../core/finance_categories.dart';
import '../core/utils.dart';
import '../models/body.dart';
import '../models/day_snapshot.dart';
import '../models/life_event.dart';
import '../models/life_process.dart';
import '../models/models.dart';
import 'default_data.dart';

/// Версия схемы сохранённых данных. Увеличивать при несовместимых изменениях
/// и добавлять шаг миграции в репозиторий.
/// 4 — журнал событий жизни (`events`). 5 — процессы (`processes`) и связь событий с ними.
/// 6 — дневные снимки (`snapshots`) вместо недельных массивов (старые массивы переносятся при чтении).
/// 7 — план ресурсов цели (`goals[].plan`). 8 — связь узла графа с процессом или целью (`graphNodes[].ref`).
/// 9 — основная валюта (`currency`).
/// 10 — тело: замеры веса (`weights`), рост (`heightCm`), цель по весу (`bodyGoal`).
const int kSchemaVersion = 10;

/// Предел журналов в памяти (при превышении удаляются самые старые). Хранилище (SQLite) пишет только
/// изменения, но весь журнал пока загружается в память целиком — поэтому предел сохранён.
const int kMaxWorkoutSets = 50000;
const int kMaxTransactions = 50000;

/// Предел журнала событий. В отличие от подходов и операций старые события НЕ вытесняются
/// (это была бы потеря истории): по достижении предела новые события не принимаются.
const int kMaxLifeEvents = 50000;

/// Предел числа процессов (они хранятся в таблице малых данных и сравниваются целиком при сохранении).
const int kMaxProcesses = 1000;

/// Предел дневных снимков (сто лет). Старые снимки не вытесняются.
const int kMaxSnapshots = 36500;

/// Весь сохраняемый срез состояния приложения (чистые данные, без UI и без Flutter-зависимостей логики).
class AppData {
  int netWorth;
  int monthlyIncome;
  int monthlyExpense;
  int dailySteps;
  int activeCalories;
  int proteinGrams;
  String lastDay; // yyyy-MM-dd последнего открытия — для сдвига недельных историй
  Map<String, MuscleGroup> muscles;
  List<GlobalGoal> goals;
  List<AchievementItem> achievements;
  List<SalaryStep> salaryHistory;
  List<GraphNode> graphNodes;
  List<GraphEdge> graphEdges;
  /// Дневные снимки по ключу дня (yyyy-MM-dd), по возрастанию дат.
  SplayTreeMap<String, DaySnapshot> snapshots;
  List<WorkoutSet> workoutSets; // журнал подходов, по возрастанию времени
  List<MoneyTx> transactions; // денежные операции, по возрастанию времени
  Map<String, int> budgets; // лимит расходов в месяц по категории, ₽
  List<RecurringTx> recurring; // правила повторяющихся операций
  List<LifeProcess> processes; // процессы жизни (длительные направления усилий)
  List<WeightEntry> weights; // замеры веса, по возрастанию времени
  int? heightCm; // рост, см; null — не указан
  String? bodyGoal; // цель по весу (BodyGoal); null — не выбрана
  List<LifeEvent> events; // журнал событий жизни (все версии, включая отменённые), по возрастанию времени
  String userName; // как обращаться (пусто — без имени)
  int stepsGoal; // цель шагов в день
  int proteinGoal; // норма белка, г в день
  bool onboardingDone; // знакомство пройдено
  bool healthEnabled; // подключён Health Connect (автосинхронизация включена)
  String currency; // код основной валюты (RUB, USD…): только обозначение, суммы не пересчитываются
  int? lastHealthSyncMs;

  AppData({
    required this.netWorth,
    required this.monthlyIncome,
    required this.monthlyExpense,
    required this.dailySteps,
    required this.activeCalories,
    required this.proteinGrams,
    required this.lastDay,
    required this.muscles,
    required this.goals,
    required this.achievements,
    required this.salaryHistory,
    required this.graphNodes,
    required this.graphEdges,
    Map<String, DaySnapshot>? snapshots,
    List<WorkoutSet>? workoutSets,
    List<MoneyTx>? transactions,
    Map<String, int>? budgets,
    List<RecurringTx>? recurring,
    List<LifeEvent>? events,
    List<LifeProcess>? processes,
    List<WeightEntry>? weights,
    this.heightCm,
    this.bodyGoal,
    this.userName = '',
    this.stepsGoal = 10000,
    this.proteinGoal = 140,
    this.onboardingDone = true,
    this.healthEnabled = false,
    this.currency = kDefaultCurrency,
    this.lastHealthSyncMs,
  })  : workoutSets = workoutSets ?? <WorkoutSet>[],
        transactions = transactions ?? <MoneyTx>[],
        budgets = budgets ?? <String, int>{},
        recurring = recurring ?? <RecurringTx>[],
        snapshots = SplayTreeMap.of(snapshots ?? const {}),
        events = events ?? <LifeEvent>[],
        processes = processes ?? <LifeProcess>[],
        weights = weights ?? <WeightEntry>[];

  factory AppData.defaults({DateTime? now}) => AppData(
        netWorth: 2450000,
        monthlyIncome: 380000,
        monthlyExpense: 160000,
        dailySteps: 8420,
        activeCalories: 540,
        proteinGrams: 145,
        lastDay: dayKey(now ?? DateTime.now()),
        muscles: defaultMuscles(now: now),
        goals: defaultGoals(),
        achievements: defaultAchievements(),
        salaryHistory: defaultSalary(),
        graphNodes: defaultGraphNodes(),
        graphEdges: defaultGraphEdges(),
        snapshots: snapshotsFromWeekly(
          lastDay: dayKey(now ?? DateTime.now()),
          steps: const [6800, 7400, 9200, 6100, 8900, 11400, 8420],
          calories: const [450, 490, 610, 380, 560, 710, 540],
          nodes: const [3, 4, 6, 7, 8, 8, 9],
          netWorth: 2450000,
          protein: 145,
        ),
        workoutSets: <WorkoutSet>[],
        userName: 'Александр', // имя из исходной версии приложения; для существующих данных остаётся прежним
        onboardingDone: true,
      );

  /// Чистый старт для новой установки: нули, пустые журналы и цели, только «живые» узлы графа.
  /// Знакомство ещё не пройдено ([onboardingDone] = false).
  factory AppData.blank({DateTime? now}) {
    final nodes = blankGraphNodes();
    return AppData(
      netWorth: 0,
      monthlyIncome: 0,
      monthlyExpense: 0,
      dailySteps: 0,
      activeCalories: 0,
      proteinGrams: 0,
      lastDay: dayKey(now ?? DateTime.now()),
      muscles: blankMuscles(),
      goals: <GlobalGoal>[],
      achievements: <AchievementItem>[],
      salaryHistory: <SalaryStep>[],
      graphNodes: nodes,
      graphEdges: blankGraphEdges(),
      onboardingDone: false,
    );
  }

  /// [includeLogs] = false пропускает журналы подходов и операций (самые крупные части):
  /// репозиторий сохраняет их точечно через [ChangeSet] и не должен сериализовать каждый раз.
  Map<String, dynamic> toJson({bool includeLogs = true}) => {
        'schemaVersion': kSchemaVersion,
        'netWorth': netWorth,
        'monthlyIncome': monthlyIncome,
        'monthlyExpense': monthlyExpense,
        'dailySteps': dailySteps,
        'activeCalories': activeCalories,
        'proteinGrams': proteinGrams,
        'lastDay': lastDay,
        'muscles': muscles.map((k, v) => MapEntry(k, v.toJson())),
        'goals': goals.map((g) => g.toJson()).toList(),
        'achievements': achievements.map((a) => a.toJson()).toList(),
        'salaryHistory': salaryHistory.map((s) => s.toJson()).toList(),
        'graphNodes': graphNodes.map((n) => n.toJson()).toList(),
        'graphEdges': graphEdges.map((e) => e.toJson()).toList(),
        if (includeLogs) 'workoutSets': workoutSets.map((w) => w.toJson()).toList(),
        if (includeLogs) 'transactions': transactions.map((t) => t.toJson()).toList(),
        if (includeLogs) 'events': events.map((e) => e.toJson()).toList(),
        if (includeLogs) 'snapshots': snapshots.values.map((x) => x.toJson()).toList(),
        'budgets': budgets,
        'recurring': recurring.map((r) => r.toJson()).toList(),
        'processes': processes.map((p) => p.toJson()).toList(),
        'weights': weights.map((w) => w.toJson()).toList(),
        'heightCm': heightCm,
        'bodyGoal': bodyGoal,
        'userName': userName,
        'stepsGoal': stepsGoal,
        'proteinGoal': proteinGoal,
        'onboardingDone': onboardingDone,
        'healthEnabled': healthEnabled,
        'currency': currency,
        'lastHealthSyncMs': lastHealthSyncMs,
      };

  /// Толерантный разбор: отсутствующее или повреждённое поле заменяется значением по умолчанию
  /// (и логируется), остальные поля не страдают.
  factory AppData.fromJson(Map<String, dynamic> j, {DateTime? now, bool strict = false}) {
    final d = AppData.defaults(now: now);

    T pick<T>(String key, T Function(dynamic) parse, T fallback) {
      final v = j[key];
      if (v == null) {
        // Missing fields are valid in older schemas; explicit null is not valid for
        // required exported fields. lastHealthSyncMs, heightCm and bodyGoal are intentionally nullable.
        if (strict && j.containsKey(key) && !const {'lastHealthSyncMs', 'heightCm', 'bodyGoal'}.contains(key)) {
          throw FormatException('AppData: поле "$key" не может быть null');
        }
        return fallback;
      }
      try {
        return parse(v);
      } catch (e, st) {
        AppLog.e('AppData: поле "$key" повреждено, использовано значение по умолчанию', e, st);
        if (strict) rethrow;
        return fallback;
      }
    }

    List<T> list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
        (v as List).map((e) => f(e as Map<String, dynamic>)).toList();

    List<T> uniqueCollection<T>(
      dynamic v,
      String field,
      T Function(Map<String, dynamic>) parse,
      String Function(T) keyOf,
    ) {
      final entries = list(v, parse);
      // docs uses (collection, id) as its primary key. Reject collisions on
      // backup import before _docsFrom can collapse records into its Map.
      if (strict) {
        final seen = <String>{};
        for (final entry in entries) {
          final key = keyOf(entry);
          if (!seen.add(key)) {
            throw FormatException(
              'AppData: поле "$field" содержит повторяющийся ключ "$key"',
            );
          }
        }
      }
      return entries;
    }
    List<T> boundedJournal<T>(
      dynamic v,
      int maxLength,
      String field,
      T Function(Map<String, dynamic>) parse, {
      String Function(T)? idOf,
    }) {
      final entries = v as List;
      // Existing local data remains readable for compatibility. User-imported backups
      // must respect the same memory bounds enforced by controller mutations.
      if (strict && entries.length > maxLength) {
        throw FormatException(
          'AppData: поле "$field" превышает допустимый размер ($maxLength)',
        );
      }
      final parsed = entries
          .map((e) => parse(e as Map<String, dynamic>))
          .toList();
      // SQLite stores journal IDs as primary keys. ConflictAlgorithm.replace
      // would silently overwrite an earlier row if an imported backup repeats an ID.
      // Keep legacy/local parsing tolerant; enforce uniqueness on strict imports only.
      if (strict && idOf != null) {
        final seenIds = <String>{};
        for (final entry in parsed) {
          final id = idOf(entry);
          if (!seenIds.add(id)) {
            throw FormatException(
              'AppData: поле "$field" содержит повторяющийся id "$id"',
            );
          }
        }
      }
      return parsed;
    }

    return AppData(
      netWorth: pick<int>('netWorth', (v) => (v as num).toInt(), d.netWorth),
      monthlyIncome: pick<int>('monthlyIncome', (v) => (v as num).toInt(), d.monthlyIncome),
      monthlyExpense: pick<int>('monthlyExpense', (v) => (v as num).toInt(), d.monthlyExpense),
      dailySteps: pick<int>('dailySteps', (v) => (v as num).toInt(), d.dailySteps),
      activeCalories: pick<int>('activeCalories', (v) => (v as num).toInt(), d.activeCalories),
      proteinGrams: pick<int>('proteinGrams', (v) => (v as num).toInt(), d.proteinGrams),
      lastDay: pick<String>('lastDay', (v) => v as String, d.lastDay),
      muscles: pick<Map<String, MuscleGroup>>(
        'muscles',
        (v) => (v as Map<String, dynamic>).map((k, x) => MapEntry(k, MuscleGroup.fromJson(x as Map<String, dynamic>))),
        d.muscles,
      ),
      goals: pick<List<GlobalGoal>>('goals', (v) => uniqueCollection(v, 'goals', GlobalGoal.fromJson, (entry) => entry.id), d.goals),
      achievements: pick<List<AchievementItem>>('achievements', (v) => uniqueCollection(v, 'achievements', AchievementItem.fromJson, (entry) => entry.id), d.achievements),
      salaryHistory: pick<List<SalaryStep>>('salaryHistory', (v) => list(v, SalaryStep.fromJson), d.salaryHistory),
      graphNodes: pick<List<GraphNode>>('graphNodes', (v) => uniqueCollection(v, 'graphNodes', GraphNode.fromJson, (entry) => entry.id), d.graphNodes),
      graphEdges: pick<List<GraphEdge>>('graphEdges', (v) => uniqueCollection(v, 'graphEdges', GraphEdge.fromJson, (entry) => entry.key), d.graphEdges),
      snapshots: j.containsKey('snapshots')
          ? pick<Map<String, DaySnapshot>>('snapshots', (v) => _parseSnapshots(v, strict: strict), {})
          : _migrateWeekly(j, pick, fallbackDay: j['lastDay'] is String ? j['lastDay'] as String : d.lastDay),
      workoutSets: pick<List<WorkoutSet>>(
        'workoutSets',
        (v) => (boundedJournal(v, kMaxWorkoutSets, 'workoutSets', WorkoutSet.fromJson, idOf: (entry) => entry.id)..sort((a, b) => a.at.compareTo(b.at))),
        d.workoutSets,
      ),
      transactions: pick<List<MoneyTx>>(
        'transactions',
        (v) => (boundedJournal(v, kMaxTransactions, 'transactions', MoneyTx.fromJson, idOf: (entry) => entry.id)..sort((a, b) => a.at.compareTo(b.at))),
        d.transactions,
      ),
      processes: pick<List<LifeProcess>>('processes', (v) {
        final list = uniqueCollection(v, 'processes', LifeProcess.fromJson, (entry) => entry.id);
        if (strict && list.length > kMaxProcesses) {
          throw const FormatException('AppData: поле "processes" превышает допустимый размер ($kMaxProcesses)');
        }
        return list;
      }, <LifeProcess>[]),
      events: pick<List<LifeEvent>>('events', (v) => _parseEvents(v, strict: strict), <LifeEvent>[]),
      budgets: pick<Map<String, int>>(
        'budgets',
        (v) => (v as Map).map((k, x) => MapEntry(k as String, (x as num).toInt())),
        d.budgets,
      ),
      recurring: pick<List<RecurringTx>>(
        'recurring',
        (v) {
          final rules = uniqueCollection(v, 'recurring', RecurringTx.fromJson, (entry) => entry.id);
          if (strict) {
            for (final rule in rules) {
              if (finCategory(rule.categoryId) == null) {
                throw FormatException('AppData: неизвестная категория повторяющейся операции "${rule.categoryId}"');
              }
            }
          }
          return rules;
        },
        d.recurring,
      ),
      userName: pick<String>('userName', (v) => v as String, d.userName),
      stepsGoal: pick<int>('stepsGoal', (v) => (v as num).toInt(), d.stepsGoal),
      proteinGoal: pick<int>('proteinGoal', (v) => (v as num).toInt(), d.proteinGoal),
      // старые данные без поля: пользователь уже работал с приложением — знакомство не показываем
      onboardingDone: pick<bool>('onboardingDone', (v) => v as bool, true),
      healthEnabled: pick<bool>('healthEnabled', (v) => v as bool, false),
      // старые данные без поля — рубли (единственная валюта прежних версий)
      weights: pick<List<WeightEntry>>('weights', (v) {
        final list = uniqueCollection(v, 'weights', WeightEntry.fromJson, (entry) => entry.id);
        if (strict && list.length > kMaxSnapshots) {
          throw const FormatException('AppData: поле "weights" превышает допустимый размер ($kMaxSnapshots)');
        }
        return list..sort((a, b) => a.at.compareTo(b.at));
      }, <WeightEntry>[]),
      heightCm: pick<int?>('heightCm', (v) {
        final h = (v as num).toInt();
        if (h < 50 || h > 272 || v != h) throw FormatException('AppData: недопустимый рост $v');
        return h;
      }, null),
      bodyGoal: pick<String?>('bodyGoal', (v) {
        if (v is! String || !BodyGoal.isValid(v)) throw FormatException('AppData: неизвестная цель по весу "$v"');
        return v;
      }, null),
      currency: pick<String>('currency', (v) {
        if (v is! String || currencyByCode(v) == null) throw FormatException('AppData: неизвестная валюта "$v"');
        return v;
      }, kDefaultCurrency),
      lastHealthSyncMs: pick<int?>('lastHealthSyncMs', (v) => (v as num).toInt(), null),
    );
  }

  static Map<String, DaySnapshot> _parseSnapshots(dynamic v, {required bool strict}) {
    final raw = v as List;
    if (strict && raw.length > kMaxSnapshots) {
      throw const FormatException('AppData: поле "snapshots" превышает допустимый размер ($kMaxSnapshots)');
    }
    final out = <String, DaySnapshot>{};
    for (var i = 0; i < raw.length; i++) {
      final e = raw[i];
      final s = e is Map ? DaySnapshot.tryFromJson(Map<String, dynamic>.from(e)) : null;
      if (s == null || out.containsKey(s.day)) {
        if (strict) throw FormatException('AppData: поле "snapshots" — запись #$i повреждена или повторяет день');
        AppLog.e('AppData: снимок дня #$i пропущен (повреждён или повторяет день)');
        continue;
      }
      out[s.day] = s;
    }
    return out;
  }

  /// Данные до схемы 6: недельные массивы → снимки. Массивов нет — снимков нет (а не демо-значения).
  static Map<String, DaySnapshot> _migrateWeekly(
    Map<String, dynamic> j,
    T Function<T>(String, T Function(dynamic), T) pick, {
    required String fallbackDay,
  }) {
    const keys = ['stepsWeekHistory', 'caloriesWeekHistory', 'graphEvolutionHistory'];
    if (!keys.any(j.containsKey)) return {};
    final lastDay = fallbackDay;
    // без дополнения до 7 значений: недостающие дни остаются «неизвестно», а не копией соседнего
    List<double> arr(String k) => pick<List<double>>(k, (v) => (v as List).map((e) => (e as num).toDouble()).toList(), const []);
    final nw = j['netWorth'], pr = j['proteinGrams'], ds = j['dailySteps'], dc = j['activeCalories'];
    return snapshotsFromWeekly(
      lastDay: lastDay,
      steps: arr(keys[0]),
      calories: arr(keys[1]),
      nodes: arr(keys[2]),
      netWorth: nw is num ? nw.toInt() : null,
      protein: pr is num ? pr.toInt() : null,
      todaySteps: ds is num ? ds.toInt() : null,
      todayCalories: dc is num ? dc.toInt() : null,
    );
  }

  /// Журнал событий. Строгий режим (импорт копии) отвергает копию при любой битой записи, повторе id,
  /// нарушении цепочек версий или превышении предела. Обычная загрузка пропускает только битые записи
  /// (с записью в журнал диагностики) — остальная история не теряется.
  static List<LifeEvent> _parseEvents(dynamic v, {required bool strict}) {
    final raw = v as List;
    if (strict && raw.length > kMaxLifeEvents) {
      throw const FormatException('AppData: поле "events" превышает допустимый размер ($kMaxLifeEvents)');
    }
    final out = <LifeEvent>[];
    final ids = <String>{};
    for (var i = 0; i < raw.length; i++) {
      final e = raw[i];
      final ev = e is Map ? LifeEvent.tryFromJson(Map<String, dynamic>.from(e)) : null;
      if (ev == null || !ids.add(ev.id)) {
        if (strict) throw FormatException('AppData: поле "events" — запись #$i повреждена или повторяет id');
        AppLog.e('AppData: событие #$i пропущено (повреждено или повторяет id)');
        continue;
      }
      out.add(ev);
    }
    if (strict) {
      final problem = eventJournalProblem(out);
      if (problem != null) throw FormatException('AppData: поле "events": $problem');
    }
    out.sort(compareEvents);
    return out;
  }
}

/// Снимки из прежних недельных массивов (7 значений, последнее — [lastDay]). Ноль в старых массивах
/// означал и «ноль», и «нет данных» (дни без открытия приложения заполнялись нулями), поэтому нулевые
/// шаги и калории переносятся как «неизвестно». Капитал и белок известны только за [lastDay].
/// За сам [lastDay] источник правды — текущие счётчики ([todaySteps], [todayCalories]): последняя точка
/// массивов всегда повторяла их.
Map<String, DaySnapshot> snapshotsFromWeekly({
  required String lastDay,
  required List<num> steps,
  required List<num> calories,
  required List<num> nodes,
  int? netWorth,
  int? protein,
  int? todaySteps,
  int? todayCalories,
}) {
  if (!isValidDayKey(lastDay)) return {};
  final last = dayFromKey(lastDay);
  final out = <String, DaySnapshot>{};
  num? at(List<num> l, int i) => i < l.length ? l[l.length - 1 - i] : null; // i — дней назад
  for (var i = 0; i < 7; i++) {
    final key = dayKey(DateTime(last.year, last.month, last.day - i));
    final st = i == 0 && todaySteps != null ? todaySteps : at(steps, i);
    final kc = i == 0 && todayCalories != null ? todayCalories : at(calories, i);
    final nd = at(nodes, i);
    final s = DaySnapshot(
      day: key,
      steps: st != null && st > 0 ? st.round() : null,
      activeCalories: kc != null && kc > 0 ? kc.round() : null,
      graphNodes: nd != null && nd >= 0 ? nd.round() : null,
      netWorth: i == 0 ? netWorth : null,
      protein: i == 0 && protein != null && protein > 0 ? protein : null,
    );
    if (!s.isEmpty) out[key] = s;
  }
  return out;
}

/// Порядок журнала событий: по времени события, затем по времени записи и id (стабильно для версий).
int compareEvents(LifeEvent a, LifeEvent b) {
  final c = a.at.compareTo(b.at);
  if (c != 0) return c;
  final r = a.recordedAt.compareTo(b.recordedAt);
  return r != 0 ? r : a.id.compareTo(b.id);
}
