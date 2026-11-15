import 'package:flutter/material.dart';

import '../../core/life_events.dart';
import '../../core/resource_stats.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/life_event.dart';
import '../../state/app_controller.dart';
import '../widgets/event_dialog.dart';
import '../widgets/process_ui.dart';
import 'events_screen.dart';

/// Ресурсы: куда за период ушли время, деньги и энергия — по измерениям и процессам.
/// Без единого индекса и без «оценок»: только суммы указанного и честный счёт неуказанного.
class ResourcesScreen extends StatefulWidget {
  final AppController controller;
  final int initialDays;
  const ResourcesScreen({super.key, required this.controller, this.initialDays = 7});

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  AppController get c => widget.controller;
  late int _days = widget.initialDays;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('РЕСУРСЫ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
        backgroundColor: AppColors.panel,
        elevation: 0,
      ),
      body: ListenableBuilder(listenable: c, builder: (context, _) => _content()),
    );
  }

  Widget _content() {
    final b = c.resourceBreakdownFor(_days);
    final period = resourcePeriods.firstWhere((p) => p.days == _days);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final p in resourcePeriods)
              ChoiceChip(key: ValueKey('period_${p.days}'), label: Text(p.label), selected: _days == p.days, onSelected: (_) => setState(() => _days = p.days)),
          ],
        ),
        const SizedBox(height: 4),
        Text('${dayKey(b.from)} — ${dayKey(b.to.subtract(const Duration(days: 1)))}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 12),
        if (b.total.events == 0)
          _Card(
            title: 'ЗА ПЕРИОД СОБЫТИЙ НЕТ',
            children: [
              const Text(
                'Ресурсы считаются по событиям: отмечайте в них время, деньги и энергию — и здесь будет видно, куда они уходят.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventsScreen(controller: c))),
                  child: const Text('К событиям'),
                ),
              ),
            ],
          )
        else ...[
          _totalCard(b, period),
          const SizedBox(height: 12),
          _dimensionCard(b),
          const SizedBox(height: 12),
          _processCard(b),
        ],
        const SizedBox(height: 12),
        _Card(
          title: 'РАСХОДЫ ПО ЖУРНАЛУ ОПЕРАЦИЙ',
          children: [
            Text(
              b.financeExpenseCount == 0 ? 'Операций расхода за период нет' : '${fmtMoney(b.financeExpense)} ₽ · операций: ${b.financeExpenseCount}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            const Text(
              'Отдельный источник: деньги в событиях и операции финансов не складываются друг с другом.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  Widget _totalCard(ResourceBreakdown b, ResourcePeriod period) {
    final t = b.total;
    final p = b.previous;
    final hours = b.elapsedMinutes ~/ 60;
    return _Card(
      title: 'УЧТЕНО: событий ${t.events}',
      children: [
        for (final line in resourceLines(t)) Text(line, style: const TextStyle(fontSize: 13)),
        if (t.minutesKnown > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Записано ${fmtMinutes(t.minutes)} из $hours ч, прошедших с начала периода. Остальное время не отмечено — это не «потеря», а просто не записано.',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Предыдущие ${period.label.toLowerCase()}: событий ${p.events}'
          '${p.minutesKnown > 0 ? ' · время ${fmtMinutes(p.minutes)}' : ''}'
          '${p.moneyKnown > 0 ? ' · деньги ${fmtMoney(p.money)} ₽' : ''}',
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  Widget _dimensionCard(ResourceBreakdown b) {
    final total = b.total;
    final multi = b.byDimension.values.fold(0, (a, s) => a + s.events) > total.events;
    return _Card(
      title: 'ПО ИЗМЕРЕНИЯМ',
      children: [
        if (total.minutes > 0) ...[
          const _Sub('Время'),
          for (final d in LifeDimension.all)
            _Bar(
              label: LifeDimension.labels[d]!,
              value: b.byDimension[d]!.minutes,
              max: total.minutes,
              color: dimensionChartColor(d),
              text: _known(b.byDimension[d]!, b.byDimension[d]!.minutesKnown, fmtMinutes(b.byDimension[d]!.minutes)),
            ),
        ],
        if (total.money > 0) ...[
          const _Sub('Деньги'),
          for (final d in LifeDimension.all)
            _Bar(
              label: LifeDimension.labels[d]!,
              value: b.byDimension[d]!.money,
              max: total.money,
              color: dimensionChartColor(d),
              text: _known(b.byDimension[d]!, b.byDimension[d]!.moneyKnown, '${fmtMoney(b.byDimension[d]!.money)} ₽'),
            ),
        ],
        const _Sub('События и энергия'),
        for (final d in LifeDimension.all)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '${LifeDimension.labels[d]}: событий ${b.byDimension[d]!.events}'
              '${b.byDimension[d]!.energyKnown == 0 ? '' : ' · энергия ${_energy(b.byDimension[d]!)}'}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        if (multi)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Событие нескольких измерений учтено в каждом из них, поэтому по измерениям суммы больше общего итога.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _processCard(ResourceBreakdown b) {
    final titles = {for (final p in c.processes) p.id: p.title};
    final maxMin = [for (final s in b.byProcess) s.summary.minutes, b.withoutProcess.minutes].fold(0, (a, v) => v > a ? v : a);
    String detail(ResourceSummary s) => [
          'событий ${s.events}',
          if (s.minutesKnown > 0) fmtMinutes(s.minutes),
          if (s.moneyKnown > 0) '${fmtMoney(s.money)} ₽',
        ].join(' · ');
    return _Card(
      title: 'ПО ПРОЦЕССАМ',
      children: [
        if (b.byProcess.isEmpty)
          const Text('События периода не отнесены ни к одному процессу.', style: TextStyle(color: Colors.white54, fontSize: 12)),
        for (final s in b.byProcess)
          InkWell(
            onTap: titles.containsKey(s.processId)
                ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventsScreen(controller: c, processId: s.processId)))
                : null,
            child: _Bar(
              label: titles[s.processId] ?? 'процесс удалён',
              value: s.summary.minutes,
              max: maxMin,
              color: const Color(0xFF7A8699), // одна нейтральная заливка: процесс опознаётся подписью, а не цветом
              text: detail(s.summary),
            ),
          ),
        if (b.withoutProcess.events > 0 && b.byProcess.isNotEmpty)
          _Bar(label: 'Вне процессов', value: b.withoutProcess.minutes, max: maxMin, color: const Color(0xFF4A5261), text: detail(b.withoutProcess)),
        if (b.byProcess.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Длина полосы — указанное время.', style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),
      ],
    );
  }

  static String _known(ResourceSummary s, int known, String value) =>
      known == 0 ? '—' : known == s.events ? value : '$value · указано в $known из ${s.events}';

  static String _energy(ResourceSummary s) => [for (var i = 1; i <= 5; i++) if (s.energy[i] != null) '$i×${s.energy[i]}'].join(', ');
}

class _Card extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Card({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );
}

class _Sub extends StatelessWidget {
  final String text;
  const _Sub(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
      );
}

/// Горизонтальная полоса: подпись слева, значение текстом справа, длина — доля от [max].
class _Bar extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final Color color;
  final String text;
  const _Bar({required this.label, required this.value, required this.max, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final f = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
              const SizedBox(width: 8),
              Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11))),
            ],
          ),
          const SizedBox(height: 3),
          LayoutBuilder(
            builder: (context, box) => Container(
              height: 8,
              width: box.maxWidth,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(4)),
              alignment: Alignment.centerLeft,
              child: value <= 0
                  ? null
                  : Container(
                      width: (box.maxWidth * f).clamp(4.0, box.maxWidth),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
