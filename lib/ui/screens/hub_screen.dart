import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/currency.dart';
import '../../core/life_events.dart';
import '../../core/memories.dart';
import '../../core/utils.dart';
import '../../models/life_event.dart';
import '../../models/life_process.dart';
import '../../security/security_service.dart';
import '../../state/app_controller.dart';
import '../widgets/health_card.dart';
import '../widgets/event_dialog.dart';
import '../widgets/process_ui.dart';
import '../widgets/toast.dart';
import 'events_screen.dart';
import 'experiments_screen.dart';
import 'processes_screen.dart';
import 'resources_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';

/// Вкладка «Сегодня» (PRESENT): плитки состояния дня, идущие процессы, ресурсы недели. Отсюда же — запись события.
class HubScreen extends StatelessWidget {
  final AppController controller;
  final SecurityService security;
  const HubScreen({super.key, required this.controller, required this.security});

  AppController get c => controller;

  void _push(BuildContext context, Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _quickEvent(BuildContext context) async {
    if (c.eventsFull) {
      showToast(context, 'Журнал событий заполнен — новые события не принимаются');
      return;
    }
    final d = await showEventDialog(context, now: c.now, goals: c.goals, processes: c.processes);
    if (d == null || !context.mounted) return;
    final id = c.addEvent(
      title: d.title,
      dimensions: d.dimensions,
      kind: d.kind,
      at: d.at,
      note: d.note,
      cost: d.cost,
      goalIds: d.goalIds,
      processIds: d.processIds,
    );
    showToast(context, id == null ? 'Событие не сохранено: проверьте данные' : 'Событие зафиксировано');
  }

  @override
  Widget build(BuildContext context) {
    final now = c.now;
    final active = [
      for (final p in c.processes)
        if (p.status == ProcessStatus.active) p
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.userName.isEmpty ? '' : '${c.userName} · '}${_weekday(now)}, ${now.day} ${_monthGen(now)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      key: const ValueKey('today_date'),
                      style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    const Text('Сегодня', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -0.8)),
                  ],
                ),
              ),
              _RoundButton(
                icon: Icons.tune,
                tooltip: 'Настройки',
                onTap: () => _push(context, SettingsScreen(controller: c, security: security)),
              ),
              const SizedBox(width: 10),
              _RoundButton(key: const ValueKey('quick_event'), icon: Icons.add, tooltip: 'Записать событие', filled: true, onTap: () => _quickEvent(context)),
            ],
          ),
          if (c.weekReviewDue) ...[
            const SizedBox(height: 16),
            _Tile(
              key: const ValueKey('review_tile'),
              onTap: () => _push(context, ReviewScreen(controller: c)),
              child: const Row(
                children: [
                  Icon(Icons.event_note_outlined, color: AppColors.text),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Обзор недели', style: _label),
                        SizedBox(height: 2),
                        Text('Факты за 7 дней и три вопроса — пара минут', style: _sub),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.muted),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _RecoveryTile(controller: c)),
                const SizedBox(width: 12),
                Expanded(child: _StepsTile(controller: c, onTap: () => _push(context, _HealthScreen(controller: c)))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ProcessesTile(
              controller: c,
              active: active,
              onOpen: (p) => _push(context, EventsScreen(controller: c, processId: p.id)),
              onAll: () => _push(context, ProcessesScreen(controller: c))),
          const SizedBox(height: 12),
          _ResourcesTile(controller: c, onTap: () => _push(context, ResourcesScreen(controller: c))),
          for (final x in c.experiments.where((x) => !x.isFinished(now) && !now.isBefore(x.startedAt)).take(2)) ...[
            const SizedBox(height: 12),
            _Tile(
              key: ValueKey('hub_exp_${x.id}'),
              onTap: () => _push(context, ExperimentScreen(controller: c, id: x.id)),
              child: Row(
                children: [
                  const Icon(Icons.science_outlined, color: AppColors.text),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(x.title, style: _label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('Эксперимент · ${experimentStage(x, now)}', style: _sub),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.muted),
                ],
              ),
            ),
          ],
          if (c.memory != null) ...[
            const SizedBox(height: 12),
            _MemoryTile(memory: c.memory!),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('open_events'),
                  onPressed: () => _push(context, EventsScreen(controller: c)),
                  icon: const Icon(Icons.timeline, size: 18),
                  label: const Text('События'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('open_processes'),
                  onPressed: () => _push(context, ProcessesScreen(controller: c)),
                  icon: const Icon(Icons.autorenew, size: 18),
                  label: const Text('Процессы'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _weekday(DateTime d) => const ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'][d.weekday - 1];
  static String _monthGen(DateTime d) => const [
        'января',
        'февраля',
        'марта',
        'апреля',
        'мая',
        'июня',
        'июля',
        'августа',
        'сентября',
        'октября',
        'ноября',
        'декабря',
      ][d.month - 1];
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool filled;
  final VoidCallback onTap;
  const _RoundButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: filled ? AppColors.accent : AppColors.raised,
          shape: CircleBorder(side: BorderSide(color: filled ? AppColors.accent : AppColors.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 46, height: 46, child: Icon(icon, size: 21, color: filled ? Colors.black : AppColors.text, semanticLabel: tooltip)),
          ),
        ),
      );
}

/// Плитка: тёмно-серая, скруглённая, нажимаемая.
class _Tile extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  const _Tile({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.tile), side: const BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

const _sub = TextStyle(color: AppColors.muted, fontSize: 13);
const _label = TextStyle(fontSize: 16, fontWeight: FontWeight.w500);

/// Кольцо — доля восстановленных групп мышц (счёт, а не процент «готовности»).
class _RecoveryTile extends StatelessWidget {
  final AppController controller;
  const _RecoveryTile({required this.controller});

  @override
  Widget build(BuildContext context) {
    final r = controller.recovery;
    return Tooltip(
      message: 'Оценка по типовому времени восстановления групп мышц после последней тренировки',
      child: _Tile(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: CustomPaint(
                painter: _RingPainter(r.total == 0 ? 0 : r.recovered / r.total),
                child: Center(child: Text('${r.recovered}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              ),
            ),
            const SizedBox(height: 28),
            const Text('Восстановлено', style: _label),
            const SizedBox(height: 2),
            Text('${r.recovered} из ${r.total} групп · оценка', style: _sub),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  const _RingPainter(this.fraction);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(2), 0, 6.2832, false, p..color = const Color(0xFF2A2A2E));
    if (fraction > 0) canvas.drawArc(rect.deflate(2), -1.5708, 6.2832 * fraction.clamp(0.0, 1.0), false, p..color = AppColors.text);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction;
}

class _StepsTile extends StatelessWidget {
  final AppController controller;
  final VoidCallback onTap;
  const _StepsTile({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final goal = c.stepsGoal;
    final src = c.snapshotFor(c.now)?.activitySource;
    return _Tile(
      key: const ValueKey('steps_tile'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(fmtMoney(c.dailySteps), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -1)),
                const SizedBox(width: 6),
                const Text('шагов', style: TextStyle(color: AppColors.muted, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 28),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: goal <= 0 ? 0 : (c.dailySteps / goal).clamp(0.0, 1.0), minHeight: 4),
          ),
          const SizedBox(height: 8),
          Text(
            'Цель ${fmtMoney(goal)} · ${src == 'health' ? 'Health Connect' : src == 'manual' ? 'вручную' : 'нет данных'}',
            style: _sub,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

/// Идущие процессы: точечный календарь трёх месяцев для самого активного (светлая точка — в этот день
/// было событие процесса) и строки процессов. Точки — только факты из журнала событий.
class _ProcessesTile extends StatelessWidget {
  final AppController controller;
  final List<LifeProcess> active;
  final ValueChanged<LifeProcess> onOpen;
  final VoidCallback onAll;
  const _ProcessesTile({required this.controller, required this.active, required this.onOpen, required this.onAll});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (active.isEmpty) {
      return _Tile(
        onTap: onAll,
        child: const Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Процессов нет', style: _label),
                  SizedBox(height: 2),
                  Text('Начните процесс: изучение, тренировочный цикл, накопление', style: _sub),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      );
    }
    // самый активный — с последним событием позже остальных
    final acts = {for (final p in active) p.id: c.processActivityOf(p.id)};
    final sorted = [...active]..sort((a, b) {
        final la = acts[a.id]!.lastAt, lb = acts[b.id]!.lastAt;
        if (la == null) return lb == null ? 0 : 1;
        if (lb == null) return -1;
        return lb.compareTo(la);
      });
    final top = sorted.first;
    final days = {for (final e in c.eventsForProcess(top.id)) dayKey(e.at)};
    final now = c.now;
    return _Tile(
      key: const ValueKey('processes_tile'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start, // подписи месяцев на одной линии при разном числе рядов точек
            children: [
              for (var m = 2; m >= 0; m--) Expanded(child: _MonthDots(month: DateTime(now.year, now.month - m), today: now, active: days)),
            ],
          ),
          const SizedBox(height: 12),
          for (final p in sorted.take(3))
            InkWell(
              key: ValueKey('today_${p.id}'),
              onTap: () => onOpen(p),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration:
                          BoxDecoration(color: p.dimensions.isEmpty ? AppColors.muted : dimensionChartColor(p.dimensions.first), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _label),
                          Text(_processLine(acts[p.id]!), style: _sub),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
                  ],
                ),
              ),
            ),
          if (active.length > 3) TextButton(onPressed: onAll, child: Text('Все процессы (${active.length})')),
        ],
      ),
    );
  }

  static String _processLine(ProcessActivity a) => [
        'Идёт',
        'событий ${a.resources.events}',
        if (a.resources.minutesKnown > 0) fmtMinutes(a.resources.minutes),
      ].join(' · ');
}

class _MonthDots extends StatelessWidget {
  final DateTime month;
  final DateTime today;
  final Set<String> active;
  const _MonthDots({required this.month, required this.today, required this.active});

  @override
  Widget build(BuildContext context) {
    final n = DateTime(month.year, month.month + 1, 0).day;
    final isCurrent = month.year == today.year && month.month == today.month;
    final shown = isCurrent ? today.day : n; // будущие дни не рисуются
    return Column(
      children: [
        Text(monthNames[month.month - 1], style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        SizedBox(
          width: 7 * 6 + 6 * 4, // ровно 7 точек в ряд, как неделя
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var d = 1; d <= shown; d++)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active.contains(dayKey(DateTime(month.year, month.month, d))) ? AppColors.text : const Color(0xFF3A3A3E),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResourcesTile extends StatelessWidget {
  final AppController controller;
  final VoidCallback onTap;
  const _ResourcesTile({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = controller.resourceBreakdownFor(7);
    final t = b.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Tile(
          key: const ValueKey('open_resources'),
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ресурсы', style: _label),
                    const SizedBox(height: 2),
                    Text(
                      t.events == 0 ? '7 дней · событий нет' : '7 дней · время указано в ${t.minutesKnown} из ${t.events}',
                      style: _sub,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(t.minutesKnown > 0 ? fmtMinutes(t.minutes) : '—',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.4)),
                  if (t.moneyKnown > 0) Text(fmtCur(t.money), style: _sub),
                ],
              ),
            ],
          ),
        ),
        if (t.events > 0) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in LifeDimension.all)
                if (b.byDimension[d]!.events > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: tileDecoration(radius: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: dimensionChartColor(d), shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(
                          '${LifeDimension.labels[d]} ${b.byDimension[d]!.minutesKnown > 0 ? fmtMinutes(b.byDimension[d]!.minutes) : '· ${b.byDimension[d]!.events}'}',
                          style: const TextStyle(color: Color(0xFFC8C8CC), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Здоровье дня: подключение Health Connect, синхронизация, ручной ввод, неделя шагов.
class _HealthScreen extends StatelessWidget {
  final AppController controller;
  const _HealthScreen({required this.controller});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Здоровье дня')),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [HealthCard(controller: controller)]),
        ),
      );
}

/// «В этот день»: было → стало, только факты из журналов.
class _MemoryTile extends StatelessWidget {
  final Memory memory;
  const _MemoryTile({required this.memory});

  @override
  Widget build(BuildContext context) => _Tile(
        key: const ValueKey('memory_tile'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${memory.daysAgo >= 365 ? 'Год назад' : 'Месяц назад'} · ${memory.day.day} ${HubScreen._monthGen(memory.day)} ${memory.day.year}',
              style: _label,
            ),
            const SizedBox(height: 6),
            for (final l in memory.lines)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(l.text, style: const TextStyle(fontSize: 14, color: Color(0xFFC8C8CC))),
              ),
          ],
        ),
      );
}
