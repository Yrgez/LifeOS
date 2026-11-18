part of '../app_controller.dart';

/// Цели и достижения, план ресурсов цели и журнал её изменений.
/// Расширение того же library: работает с состоянием контроллера напрямую, мутации — только через `_commit`.
extension GoalOps on AppController {
  // ---------------- цели и достижения ----------------

  /// Текущее значение метрики для привязанных чекпоинтов; null — метрика недоступна (мышцы нет).
  double? metricValue(MetricLink link) {
    switch (link.kind) {
      case MetricLink.oneRM:
        return _d.muscles[link.muscleId]?.maxWeight;
      case MetricLink.netWorth:
        return netWorth.toDouble();
      case MetricLink.income:
        return incomeEvidence.toDouble();
      default:
        return null;
    }
  }

  String _linkTitle(MetricLink l) {
    switch (l.kind) {
      case MetricLink.oneRM:
        return '1RM «${_d.muscles[l.muscleId]?.name ?? l.muscleId}» ≥ ${trimNum(l.target)} кг';
      case MetricLink.netWorth:
        return 'Капитал ≥ ${fmtCur(l.target.round())}';
      default:
        return 'Доход ≥ ${fmtCur(l.target.round())} / мес';
    }
  }

  GlobalGoal? _goal(String id) => _d.goals.where((g) => g.id == id).firstOrNull;

  void addGoal(String title, String category, List<String> checkpoints, {DateTime? deadline}) {
    final t = title.trim();
    if (t.isEmpty) return;
    _commit(() {
      _d.goals.add(GlobalGoal(
        id: 'goal_${_clock().microsecondsSinceEpoch}',
        createdAt: _clock(),
        history: [GoalChange(_clock(), 'Цель поставлена')],
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
    final cat = category.trim().isEmpty ? 'Стратегия' : category.trim();
    final dl = deadline == null ? null : dateOnly(deadline);
    String d(DateTime? x) => x == null ? 'без срока' : fmtDate(x);
    _commit(() {
      if (g.title != t) _logGoal(g, 'Формулировка: «${g.title}» → «$t»');
      if (g.deadline != dl) _logGoal(g, 'Срок: ${d(g.deadline)} → ${d(dl)}');
      if (g.category != cat) _logGoal(g, 'Категория: ${g.category} → $cat');
      g.title = t;
      g.category = cat;
      g.deadline = dl;
    });
    return true;
  }

  /// Запись в журнал изменений цели (время — по часам контроллера, порядок не нарушается).
  void _logGoal(GlobalGoal g, String text) {
    var at = _clock();
    if (g.history.isNotEmpty && at.isBefore(g.history.last.at)) at = g.history.last.at;
    final x = text.length > GoalChange.maxText ? '${text.substring(0, GoalChange.maxText - 1)}…' : text;
    g.history.add(GoalChange(at, x));
  }

  static String _planText(GoalPlan? p) => p == null
      ? 'не задан'
      : [if (p.minutes != null) '${(p.minutes! / 60).round()} ч', if (p.money != null) fmtCur(p.money!)].join(', ');

  /// План ресурсов цели (минуты, рубли); null или пустой план снимает его. Значения должны быть > 0.
  bool setGoalPlan(String goalId, GoalPlan? plan) {
    final g = _goal(goalId);
    if (g == null || (plan != null && !plan.isValid)) return false;
    final next = plan == null || plan.isEmpty ? null : plan;
    _commit(() {
      if (_planText(g.plan) != _planText(next)) _logGoal(g, 'План ресурсов: ${_planText(g.plan)} → ${_planText(next)}');
      g.plan = next;
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
          at: _clock(),
          category: category.trim().isEmpty ? 'Личный рекорд' : category.trim(),
        ),
      );
    });
  }

  void removeAchievement(String id) => _commit(() => _d.achievements.removeWhere((a) => a.id == id));
}
