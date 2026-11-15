import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/life_event.dart';
import '../../models/life_process.dart';
import '../../state/app_controller.dart';
import '../widgets/event_dialog.dart';
import '../widgets/process_ui.dart';
import '../widgets/toast.dart';
import 'events_screen.dart';

/// Процессы жизни: идущие и на паузе сверху, завершённые и прекращённые — ниже (история не прячется).
class ProcessesScreen extends StatefulWidget {
  final AppController controller;
  const ProcessesScreen({super.key, required this.controller});

  @override
  State<ProcessesScreen> createState() => _ProcessesScreenState();
}

class _ProcessesScreenState extends State<ProcessesScreen> {
  AppController get c => widget.controller;
  String? _dimension;

  Future<void> _add() async {
    final d = await showProcessDialog(context, now: c.now, goals: c.goals);
    if (d == null || !mounted) return;
    final id = c.addProcess(title: d.title, dimensions: d.dimensions, description: d.description, goalIds: d.goalIds, startedAt: d.startedAt);
    if (id == null) showToast(context, 'Процесс не сохранён: проверьте данные');
  }

  void _open(LifeProcess p) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventsScreen(controller: c, processId: p.id)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ПРОЦЕССЫ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
        backgroundColor: AppColors.panel,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add_process'),
        backgroundColor: AppColors.green,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Процесс', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _add,
      ),
      body: ListenableBuilder(listenable: c, builder: (context, _) => _content()),
    );
  }

  Widget _content() {
    final list = [for (final p in c.processes) if (_dimension == null || p.touches(_dimension!)) p];
    final open = [for (final p in list) if (p.isOpen) p];
    final closed = [for (final p in list) if (!p.isOpen) p]..sort((a, b) => b.endedAt!.compareTo(a.endedAt!));
    Widget card(LifeProcess p) => ProcessCard(key: ValueKey(p.id), process: p, activity: c.processActivityOf(p.id), onTap: () => _open(p));
    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Text(t, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(label: const Text('Все'), selected: _dimension == null, onSelected: (_) => setState(() => _dimension = null)),
            for (final d in LifeDimension.all)
              ChoiceChip(
                label: Text(LifeDimension.labels[d]!),
                selected: _dimension == d,
                selectedColor: dimensionColor(d).withValues(alpha: 0.3),
                onSelected: (_) => setState(() => _dimension = d),
              ),
          ],
        ),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'Процессов пока нет. Процесс — длительное направление: изучение языка, тренировочный цикл, '
              'накопление на цель. Отмечайте события процесса — и будет видно, сколько в него вложено.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
        if (open.isNotEmpty) ...[section('ИДУТ И НА ПАУЗЕ'), for (final p in open) card(p)],
        if (closed.isNotEmpty) ...[section('ЗАВЕРШЁННЫЕ И ПРЕКРАЩЁННЫЕ'), for (final p in closed) card(p)],
      ],
    );
  }
}
