import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/workout_stats.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../../models/life_event.dart';
import '../screens/events_screen.dart';
import 'event_dialog.dart';
import 'form_dialog.dart';
import 'process_ui.dart';

/// Диалог создания цели.
Future<void> showNewGoalDialog(BuildContext context, AppController c) async {
  final r = await showFormDialog(
    context,
    title: 'Новая глобальная цель (OKR)',
    actionLabel: 'Создать',
    accent: AppColors.violet,
    actionTextColor: Colors.white,
    fields: const [
      FieldSpec('t', 'Формулировка цели'),
      FieldSpec('c', 'Категория', initial: 'Стратегия'),
      FieldSpec('dl', 'Срок (дд.мм.гггг, можно пусто)'),
      FieldSpec('cp', 'Чекпоинты (каждый с новой строки)', lines: 4),
    ],
    validate: (v) => v['t']!.isNotEmpty && (v['dl']!.isEmpty || parseDate(v['dl']!) != null),
  );
  if (r == null) return;
  c.addGoal(r['t']!, r['c']!, r['cp']!.split('\n'), deadline: parseDate(r['dl']!));
}

Future<void> showEditGoalDialog(BuildContext context, AppController c, GlobalGoal g) async {
  final r = await showFormDialog(
    context,
    title: 'Изменить цель',
    actionLabel: 'Сохранить',
    accent: AppColors.violet,
    actionTextColor: Colors.white,
    fields: [
      FieldSpec('t', 'Формулировка цели', initial: g.title),
      FieldSpec('c', 'Категория', initial: g.category),
      FieldSpec('dl', 'Срок (дд.мм.гггг, пусто — без срока)', initial: g.deadline == null ? '' : fmtDate(g.deadline!)),
    ],
    validate: (v) => v['t']!.isNotEmpty && (v['dl']!.isEmpty || parseDate(v['dl']!) != null),
  );
  if (r == null) return;
  c.updateGoal(g.id, title: r['t']!, category: r['c']!, deadline: parseDate(r['dl']!));
}

/// План ресурсов цели: сколько часов и рублей вы готовы вложить. Пустое поле — не задано.
Future<void> showGoalPlanDialog(BuildContext context, AppController c, GlobalGoal g) async {
  final p = g.plan;
  bool ok(String s) => s.trim().isEmpty || (parseNum(s) ?? -1) > 0;
  final r = await showFormDialog(
    context,
    title: 'План ресурсов цели',
    actionLabel: 'Сохранить',
    accent: AppColors.violet,
    actionTextColor: Colors.white,
    fields: [
      FieldSpec('h', 'Время, часов (пусто — не задано)', numeric: true, initial: p?.minutes == null ? '' : trimNum(p!.minutes! / 60)),
      FieldSpec('m', 'Деньги, ₽ (пусто — не задано)', numeric: true, initial: p?.money?.toString() ?? ''),
    ],
    validate: (v) => ok(v['h']!) && ok(v['m']!),
  );
  if (r == null) return;
  final h = parseNum(r['h']!), m = parseNum(r['m']!);
  c.setGoalPlan(g.id, GoalPlan(minutes: h == null ? null : (h * 60).round(), money: m?.round()));
}

/// Диалог добавления чекпоинта: ручной или привязанный к метрике (выполняется автоматически).
Future<void> showAddCheckpointDialog(BuildContext context, AppController c, GlobalGoal g) async {
  final muscleOptions = {for (final e in c.muscles.entries) e.key: e.value.name};
  final r = await showFormDialog(
    context,
    title: 'Новый чекпоинт',
    actionLabel: 'Добавить',
    accent: AppColors.violet,
    actionTextColor: Colors.white,
    fields: [
      const FieldSpec('k', 'Тип', initial: 'manual', options: {
        'manual': 'Ручной — отмечаю сам',
        MetricLink.oneRM: 'Авто: рекорд 1RM мышцы ≥',
        MetricLink.netWorth: 'Авто: чистый капитал ≥',
        MetricLink.income: 'Авто: доход в месяц ≥',
      }),
      const FieldSpec('t', 'Название (для авто можно пусто)'),
      FieldSpec('m', 'Мышца (только для 1RM)', initial: muscleOptions.keys.contains('chest') ? 'chest' : muscleOptions.keys.first, options: muscleOptions),
      const FieldSpec('v', 'Целевое значение (кг или ₽)', numeric: true),
    ],
    validate: (v) => v['k'] == 'manual' ? v['t']!.isNotEmpty : (parseNum(v['v']!) ?? 0) > 0,
  );
  if (r == null) return;
  final kind = r['k']!;
  c.addCheckpoint(
    g.id,
    r['t']!,
    link: kind == 'manual'
        ? null
        : MetricLink(kind: kind, muscleId: kind == MetricLink.oneRM ? r['m'] : null, target: parseNum(r['v']!)!),
  );
}

/// Карточка цели: срок, прогресс, чекпоинты (ручные и автоматические).
class GoalCard extends StatelessWidget {
  final AppController controller;
  final GlobalGoal goal;
  const GoalCard({super.key, required this.controller, required this.goal});

  AppController get c => controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: goal.isComplete ? AppColors.green.withValues(alpha: 0.5) : Colors.white10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: Text(goal.category.toUpperCase(), overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.violet, fontSize: 10, fontWeight: FontWeight.bold))),
                  Row(
                    children: [
                      // счёт, а не процент: «2 из 5» не прячет, из чего сложился прогресс
                      Text(
                        goal.checkpoints.isEmpty ? '—' : '${goal.checkpoints.where((x) => x.isCompleted).length} из ${goal.checkpoints.length}',
                        style: const TextStyle(color: AppColors.violet, fontWeight: FontWeight.bold),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20),
                        color: AppColors.field,
                        onSelected: (v) {
                          switch (v) {
                            case 'edit':
                              showEditGoalDialog(context, c, goal);
                            case 'add':
                              showAddCheckpointDialog(context, c, goal);
                            case 'plan':
                              showGoalPlanDialog(context, c, goal);
                            case 'delete':
                              c.removeGoal(goal.id);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Изменить цель / срок')),
                          PopupMenuItem(value: 'add', child: Text('Добавить чекпоинт')),
                          PopupMenuItem(value: 'plan', child: Text('План ресурсов')),
                          PopupMenuItem(value: 'delete', child: Text('Удалить цель', style: TextStyle(color: AppColors.red))),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(goal.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              if (goal.deadline != null) _deadline(),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: LinearProgressIndicator(
                  value: goal.progress,
                  backgroundColor: const Color(0xFF222834),
                  valueColor: AlwaysStoppedAnimation(goal.isComplete ? AppColors.green : AppColors.violet),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              if (goal.checkpoints.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Чекпоинтов нет — добавьте через меню ⋮', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
              for (int i = 0; i < goal.checkpoints.length; i++) _checkpointRow(i, goal.checkpoints[i]),
              GoalResources(controller: c, goal: goal),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deadline() {
    final d = goal.deadline!;
    final left = dayIndex(d) - dayIndex(c.now);
    String text;
    Color color;
    if (goal.isComplete) {
      text = 'Срок: ${fmtDate(d)}';
      color = Colors.white38;
    } else if (left < 0) {
      text = 'Просрочено на ${-left} дн. • ${fmtDate(d)}';
      color = AppColors.red;
    } else if (left == 0) {
      text = 'Срок — сегодня';
      color = AppColors.amber;
    } else {
      text = 'Осталось $left дн. • ${fmtDate(d)}';
      color = left <= 7 ? AppColors.amber : Colors.white54;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.event, size: 13, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _checkpointRow(int index, GoalCheckpoint cp) {
    final link = cp.link;
    final current = link == null ? null : c.metricValue(link);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: cp.isCompleted,
          activeColor: AppColors.violet,
          visualDensity: VisualDensity.compact,
          // привязанные к метрике отмечаются сами
          onChanged: link == null ? (v) => c.toggleCheckpoint(goal.id, index, v ?? false) : null,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cp.title,
                  style: TextStyle(
                    fontSize: 13,
                    decoration: cp.isCompleted ? TextDecoration.lineThrough : null,
                    color: cp.isCompleted ? Colors.white38 : Colors.white,
                  ),
                ),
                if (link != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.bolt, size: 12, color: AppColors.violet),
                      const SizedBox(width: 3),
                      Text(
                        current == null ? 'метрика недоступна' : 'сейчас ${_fmt(link, current)} / ${_fmt(link, link.target)} ${link.unit}',
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ],
                  ),
                  if (current != null && !cp.isCompleted) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: (current / link.target).clamp(0.0, 1.0),
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                      backgroundColor: const Color(0xFF222834),
                      valueColor: const AlwaysStoppedAnimation(AppColors.violet),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white24, size: 16),
          tooltip: 'Удалить чекпоинт',
          onPressed: () => c.removeCheckpoint(goal.id, index),
        ),
      ],
    );
  }

  static String _fmt(MetricLink l, double v) => l.kind == MetricLink.oneRM ? trimNum(v) : fmtMoney(v.round());
}

/// План ↔ факт по цели. Факт — из событий (напрямую и через процессы цели). Без прогнозов и оценок:
/// только «вложено столько из запланированного» и где данных не хватает.
class GoalResources extends StatelessWidget {
  final AppController controller;
  final GlobalGoal goal;
  const GoalResources({super.key, required this.controller, required this.goal});

  @override
  Widget build(BuildContext context) {
    final f = controller.goalFactOf(goal.id);
    final r = f.resources;
    final plan = goal.plan;
    if (r.events == 0 && plan == null && f.processIds.isEmpty) return const SizedBox.shrink();
    final titles = {for (final p in controller.processes) p.id: p.title};
    String known(int k, String v) => k == r.events ? v : '$v · указано в $k из ${r.events}';
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Colors.white10, height: 12),
          Text(
            'ВЛОЖЕНО: событий ${r.events}'
            '${r.events > 0 && f.viaProcess > 0 ? ' (напрямую ${f.direct}, через процессы ${f.viaProcess})' : ''}',
            style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6),
          ),
          if (f.dimensions.isNotEmpty)
            Text('Затрагивает: ${f.dimensions.map((d) => LifeDimension.labels[d]).join(' + ')}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
          if (f.processIds.isNotEmpty)
            Text('Процессы: ${f.processIds.map((id) => titles[id]).join(', ')}', style: const TextStyle(color: AppColors.amber, fontSize: 11)),
          if (plan?.minutes != null || r.minutesKnown > 0)
            _PlanRow(
              label: 'Время',
              fact: r.minutesKnown == 0 ? 'не указано' : known(r.minutesKnown, fmtMinutes(r.minutes)),
              plan: plan?.minutes == null ? null : fmtMinutes(plan!.minutes!),
              ratio: plan?.minutes == null ? null : r.minutes / plan!.minutes!,
            ),
          if (plan?.money != null || r.moneyKnown > 0)
            _PlanRow(
              label: 'Деньги',
              fact: r.moneyKnown == 0 ? 'не указано' : known(r.moneyKnown, '${fmtMoney(r.money)} ₽'),
              plan: plan?.money == null ? null : '${fmtMoney(plan!.money!)} ₽',
              ratio: plan?.money == null ? null : r.money / plan!.money!,
            ),
          if (r.events > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: ValueKey('goal_events_${goal.id}'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventsScreen(controller: controller, goalId: goal.id))),
                child: Text('События цели (${r.events})', style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  final String label;
  final String fact;
  final String? plan;
  final double? ratio; // факт / план; null — плана нет
  const _PlanRow({required this.label, required this.fact, this.plan, this.ratio});

  @override
  Widget build(BuildContext context) {
    final over = (ratio ?? 0) > 1;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan == null ? '$label: $fact' : '$label: $fact из $plan по плану${over ? ' — больше плана' : ''}',
            style: const TextStyle(fontSize: 12),
          ),
          if (ratio != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: LinearProgressIndicator(
                value: ratio!.clamp(0.0, 1.0),
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                valueColor: AlwaysStoppedAnimation(dimensionChartColor(LifeDimension.mind)),
              ),
            ),
        ],
      ),
    );
  }
}
