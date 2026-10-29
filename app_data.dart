import '../core/app_log.dart';
import '../core/utils.dart';
import '../models/models.dart';
import 'default_data.dart';

/// Версия схемы сохранённых данных. Увеличивать при несовместимых изменениях
/// и добавлять шаг миграции в репозиторий.
const int kSchemaVersion = 3;

/// Предел журналов в памяти (при превышении удаляются самые старые). Хранилище (SQLite) пишет только
/// изменения, но весь журнал пока загружается в память целиком — поэтому предел сохранён.
const int kMaxWorkoutSets = 50000;
const int kMaxTransactions = 50000;

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
  List<double> stepsWeekHistory;
  List<double> caloriesWeekHistory;
  List<double> graphEvolutionHistory;
  List<WorkoutSet> workoutSets; // журнал подходов, по возрастанию времени
  List<MoneyTx> transactions; // денежные операции, по возрастанию времени
  Map<String, int> budgets; // лимит расходов в месяц по категории, ₽
  List<RecurringTx> recurring; // правила повторяющихся операций
  String userName; // как обращаться (пусто — без имени)
  int stepsGoal; // цель шагов в день
  int proteinGoal; // норма белка, г в день
  bool onboardingDone; // знакомство пройдено
  bool healthEnabled; // подключён Health Connect (автосинхронизация включена)
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
    required this.stepsWeekHistory,
    required this.caloriesWeekHistory,
    required this.graphEvolutionHistory,
    List<WorkoutSet>? workoutSets,
    List<MoneyTx>? transactions,
    Map<String, int>? budgets,
    List<RecurringTx>? recurring,
    this.userName = '',
    this.stepsGoal = 10000,
    this.proteinGoal = 140,
    this.onboardingDone = true,
    this.healthEnabled = false,
    this.lastHealthSyncMs,
  })  : workoutSets = workoutSets ?? <WorkoutSet>[],
        transactions = transactions ?? <MoneyTx>[],
        budgets = budgets ?? <String, int>{},
        recurring = recurring ?? <RecurringTx>[];

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
        stepsWeekHistory: <double>[6800, 7400, 9200, 6100, 8900, 11400, 8420],
        caloriesWeekHistory: <double>[450, 490, 610, 380, 560, 710, 540],
        graphEvolutionHistory: <double>[3, 4, 6, 7, 8, 8, 9],
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
      stepsWeekHistory: List<double>.generate(7, (_) => 0, growable: true),
      caloriesWeekHistory: List<double>.generate(7, (_) => 0, growable: true),
      graphEvolutionHistory: List<double>.generate(7, (_) => nodes.length.toDouble(), growable: true),
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
        'stepsWeekHistory': stepsWeekHistory,
        'caloriesWeekHistory': caloriesWeekHistory,
        'graphEvolutionHistory': graphEvolutionHistory,
        if (includeLogs) 'workoutSets': workoutSets.map((w) => w.toJson()).toList(),
        if (includeLogs) 'transactions': transactions.map((t) => t.toJson()).toList(),
        'budgets': budgets,
        'recurring': recurring.map((r) => r.toJson()).toList(),
        'userName': userName,
        'stepsGoal': stepsGoal,
        'proteinGoal': proteinGoal,
        'onboardingDone': onboardingDone,
        'healthEnabled': healthEnabled,
        'lastHealthSyncMs': lastHealthSyncMs,
      };

  /// Толерантный разбор: отсутствующее или повреждённое поле заменяется значением по умолчанию
  /// (и логируется), остальные поля не страдают.
  factory AppData.fromJson(Map<String, dynamic> j, {DateTime? now}) {
    final d = AppData.defaults(now: now);

    T pick<T>(String key, T Function(dynamic) parse, T fallback) {
      final v = j[key];
      if (v == null) return fallback;
      try {
        return parse(v);
      } catch (e, st) {
        AppLog.e('AppData: поле "$key" повреждено, использовано значение по умолчанию', e, st);
        return fallback;
      }
    }

    List<T> list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
        (v as List).map((e) => f(e as Map<String, dynamic>)).toList();
    List<double> doubles(dynamic v) => fit7((v as List).map((e) => (e as num).toDouble()).toList());

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
      goals: pick<List<GlobalGoal>>('goals', (v) => list(v, GlobalGoal.fromJson), d.goals),
      achievements: pick<List<AchievementItem>>('achievements', (v) => list(v, AchievementItem.fromJson), d.achievements),
      salaryHistory: pick<List<SalaryStep>>('salaryHistory', (v) => list(v, SalaryStep.fromJson), d.salaryHistory),
      graphNodes: pick<List<GraphNode>>('graphNodes', (v) => list(v, GraphNode.fromJson), d.graphNodes),
      graphEdges: pick<List<GraphEdge>>('graphEdges', (v) => list(v, GraphEdge.fromJson), d.graphEdges),
      stepsWeekHistory: pick<List<double>>('stepsWeekHistory', doubles, d.stepsWeekHistory),
      caloriesWeekHistory: pick<List<double>>('caloriesWeekHistory', doubles, d.caloriesWeekHistory),
      graphEvolutionHistory: pick<List<double>>('graphEvolutionHistory', doubles, d.graphEvolutionHistory),
      workoutSets: pick<List<WorkoutSet>>(
        'workoutSets',
        (v) => (list(v, WorkoutSet.fromJson)..sort((a, b) => a.at.compareTo(b.at))),
        d.workoutSets,
      ),
      transactions: pick<List<MoneyTx>>(
        'transactions',
        (v) => (list(v, MoneyTx.fromJson)..sort((a, b) => a.at.compareTo(b.at))),
        d.transactions,
      ),
      budgets: pick<Map<String, int>>(
        'budgets',
        (v) => (v as Map).map((k, x) => MapEntry(k as String, (x as num).toInt())),
        d.budgets,
      ),
      recurring: pick<List<RecurringTx>>('recurring', (v) => list(v, RecurringTx.fromJson), d.recurring),
      userName: pick<String>('userName', (v) => v as String, d.userName),
      stepsGoal: pick<int>('stepsGoal', (v) => (v as num).toInt(), d.stepsGoal),
      proteinGoal: pick<int>('proteinGoal', (v) => (v as num).toInt(), d.proteinGoal),
      // старые данные без поля: пользователь уже работал с приложением — знакомство не показываем
      onboardingDone: pick<bool>('onboardingDone', (v) => v as bool, true),
      healthEnabled: pick<bool>('healthEnabled', (v) => v as bool, false),
      lastHealthSyncMs: pick<int?>('lastHealthSyncMs', (v) => (v as num).toInt(), null),
    );
  }
}
