import 'package:flutter/material.dart';

import '../../core/chronicle.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/day_snapshot.dart';
import '../../models/life_event.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/event_dialog.dart';
import 'events_screen.dart';

/// Хроника (PAST): лента жизни по месяцам и дням — события, процессы, достижения и состояние дня.
class ChronicleScreen extends StatefulWidget {
  final AppController controller;
  final bool embedded; // вкладка оболочки: без собственной шапки
  const ChronicleScreen({super.key, required this.controller, this.embedded = false});

  @override
  State<ChronicleScreen> createState() => _ChronicleScreenState();
}

class _ChronicleScreenState extends State<ChronicleScreen> {
  AppController get c => widget.controller;
  String? _dimension;
  bool _quietDays = false;
  int _months = 3;

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return ListenableBuilder(listenable: c, builder: (context, _) => _content());
    return Scaffold(
      appBar: AppBar(
        title: const Text('ХРОНИКА', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
        backgroundColor: AppColors.panel,
        elevation: 0,
      ),
      body: ListenableBuilder(listenable: c, builder: (context, _) => _content()),
    );
  }

  Widget _content() {
    final entries = [for (final e in c.chronicle) if (_dimension == null || e.dimensions.contains(_dimension)) e];
    final months = groupChronicle(entries, snapshots: c.snapshotsByDay, includeQuietDays: _quietDays && _dimension == null);
    final undated = _dimension == null ? undatedAchievements(c.achievements) : <AchievementItem>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (widget.embedded)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('ХРОНИКА', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(label: const Text('Все'), selected: _dimension == null, onSelected: (_) => setState(() => _dimension = null)),
            for (final d in LifeDimension.all)
              ChoiceChip(
                label: Text(LifeDimension.labels[d]!),
                selected: _dimension == d,
                selectedColor: dimensionColor(d).withValues(alpha: 0.3),
                onSelected: (_) => setState(() => _dimension = d),
              ),
            if (_dimension == null)
              FilterChip(
                key: const ValueKey('quiet_days'),
                label: const Text('Дни без записей'),
                selected: _quietDays,
                onSelected: (v) => setState(() => _quietDays = v),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (months.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'Хроника пока пуста. Она складывается сама: из событий, процессов, достижений и состояния каждого дня.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
        for (final m in months.take(_months)) _MonthSection(month: m, controller: c),
        if (months.length > _months)
          TextButton(onPressed: () => setState(() => _months += 6), child: Text('Ранее (ещё месяцев: ${months.length - _months})')),
        if (undated.isNotEmpty) ...[
          const _Header('БЕЗ ДАТЫ'),
          for (final a in undated) _Line(icon: Icons.emoji_events_outlined, color: AppColors.green, title: a.title, detail: a.category),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
      );
}

class _MonthSection extends StatelessWidget {
  final ChronicleMonth month;
  final AppController controller;
  const _MonthSection({required this.month, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(monthYear(month.month).toUpperCase()),
        for (final e in month.monthOnly) _entry(context, e),
        for (final d in month.days)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_dayTitle(d.day), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                if (d.snapshot != null && _snapshotLine(d.snapshot!).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(_snapshotLine(d.snapshot!), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
                for (final e in d.entries) _entry(context, e),
              ],
            ),
          ),
      ],
    );
  }

  Widget _entry(BuildContext context, ChronicleEntry e) {
    final (icon, color) = switch (e.kind) {
      ChronicleKind.event => (Icons.circle, e.dimensions.isEmpty ? Colors.white38 : dimensionColor(e.dimensions.first)),
      ChronicleKind.process => (Icons.autorenew, AppColors.amber),
      _ => (Icons.emoji_events_outlined, AppColors.green),
    };
    final hasTarget = e.kind == ChronicleKind.process && controller.processById(e.refId ?? '') != null;
    return InkWell(
      onTap: hasTarget
          ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventsScreen(controller: controller, processId: e.refId)))
          : null,
      child: _Line(
        icon: icon,
        color: color,
        title: e.title,
        detail: [
          if (e.monthOnly) 'в течение месяца',
          if (e.detail.isNotEmpty) e.detail,
          if (e.dimensions.isNotEmpty) e.dimensions.map((d) => LifeDimension.labels[d]).join(' + '),
        ].join(' · '),
      ),
    );
  }

  static String _dayTitle(String key) {
    final d = dayFromKey(key);
    return '${d.day} ${monthNames[d.month - 1].toLowerCase()}, ${dayNames[d.weekday - 1]}';
  }

  /// Состояние дня: только известные значения.
  static String _snapshotLine(DaySnapshot s) => [
        if (s.steps != null) 'шаги ${fmtMoney(s.steps!)}',
        if (s.activeCalories != null) '${s.activeCalories} ккал',
        if (s.protein != null) 'белок ${s.protein} г',
        if (s.netWorth != null) 'капитал ${fmtMoney(s.netWorth!)} ₽',
      ].join(' · ');
}

class _Line extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  const _Line({required this.icon, required this.color, required this.title, required this.detail});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: icon == Icons.circle ? 8 : 14, color: color)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13)),
                  if (detail.isNotEmpty) Text(detail, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );
}
