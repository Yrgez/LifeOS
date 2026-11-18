import 'package:flutter/material.dart';

import '../../core/review.dart';
import '../../core/rhythm.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/day_checkin.dart';
import '../../models/life_event.dart';
import '../../models/life_process.dart';
import '../../state/app_controller.dart';
import '../widgets/event_dialog.dart';
import '../widgets/process_ui.dart';
import '../widgets/toast.dart';

/// Обзор недели: факты за 7 дней, решения по процессам и три вопроса. Приложение ничего не оценивает —
/// выводы делает человек, а обзор сохраняется событием и виден в хронике.
class ReviewScreen extends StatefulWidget {
  final AppController controller;
  const ReviewScreen({super.key, required this.controller});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  AppController get c => widget.controller;
  final _answers = [for (final _ in reviewQuestions) TextEditingController()];
  final _decisions = <String, String>{}; // процесс → новый статус; нет записи — «оставить как есть»

  @override
  void dispose() {
    for (final a in _answers) {
      a.dispose();
    }
    super.dispose();
  }

  void _save() {
    final id = c.saveWeekReview([for (final a in _answers) a.text], processDecisions: _decisions);
    if (id == null) {
      showToast(context, 'Нечего сохранять: ответьте хотя бы на один вопрос или примите решение по процессу');
      return;
    }
    Navigator.of(context).pop();
    showToast(context, 'Обзор сохранён — он в хронике');
  }

  @override
  Widget build(BuildContext context) {
    final f = c.weekReviewFacts;
    final b = f.breakdown;
    final checks = c.checkInSummary(7);
    final last = b.to.subtract(const Duration(days: 1));
    final prev = f.previous;
    final prevChange = prev == null ? '' : parseReviewNote(prev.note)[2];
    return Scaffold(
      appBar: AppBar(title: const Text('Обзор недели')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('${fmtDate(b.from)} — ${fmtDate(last)}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 16),
          if (prev != null) ...[
            _Tile(
              title: 'В прошлый раз · ${fmtDate(prev.at)}',
              children: [
                Text(
                  prevChange.isEmpty ? 'Решений о переменах не записано.' : 'Вы решили: $prevChange',
                  style: const TextStyle(fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          _Tile(
            title: 'Факты · событий ${b.total.events}',
            children: [
              if (b.total.events == 0) const Text('За неделю событий не записано.', style: _sub),
              if (b.total.events > 0) ...[
                for (final line in resourceLines(b.total)) Text(line, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in LifeDimension.all)
                      _Chip(
                        color: dimensionChartColor(d),
                        text: '${LifeDimension.labels[d]} · ${b.byDimension[d]!.minutesKnown > 0 ? fmtMinutes(b.byDimension[d]!.minutes) : 'событий ${b.byDimension[d]!.events}'}',
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Неделей раньше: событий ${b.previous.events}${b.previous.minutesKnown > 0 ? ' · ${fmtMinutes(b.previous.minutes)}' : ''}',
                style: _sub,
              ),
            ],
          ),
          if (checks.checked > 0) ...[
            const SizedBox(height: 12),
            _Tile(
              key: const ValueKey('review_checkins'),
              title: 'Отметки дня · ${checks.checked} из ${checks.days}',
              children: [
                if (checks.rated > 0) Text('Оценки: ${ratingDistribution(checks.ratings)}', style: const TextStyle(fontSize: 14)),
                if (checks.tags.isNotEmpty)
                  Text('Метки: ${[for (final t in checks.tags.take(6)) '${t.$1} (${t.$2})'].join(', ')}', style: const TextStyle(fontSize: 14)),
              ],
            ),
          ],
          if (f.processes.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Tile(
              title: 'Процессы',
              children: [
                for (final line in f.processes) ...[
                  const SizedBox(height: 6),
                  Text(line.process.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  Text(
                    '${ProcessStatus.labels[line.process.status]}'
                    '${line.process.rhythm == null ? '' : ' · ${rhythmNowLabel(line.process.rhythm!, c.rhythmOf(line.process.id, count: 1).first)}'}'
                    ' · ${line.week.events == 0 ? 'за неделю событий нет' : 'событий ${line.week.events}${line.week.minutesKnown > 0 ? ' · ${fmtMinutes(line.week.minutes)}' : ''}'}',
                    style: _sub,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final opt in _options(line.process))
                        ChoiceChip(
                          key: ValueKey('decide_${line.process.id}_${opt.status ?? 'keep'}'),
                          label: Text(opt.label),
                          selected: _decisions[line.process.id] == opt.status,
                          onSelected: (_) => setState(() {
                            if (opt.status == null) {
                              _decisions.remove(line.process.id);
                            } else {
                              _decisions[line.process.id] = opt.status!;
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ],
          const SizedBox(height: 20),
          for (var i = 0; i < reviewQuestions.length; i++) ...[
            Text(reviewQuestions[i], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              key: ValueKey('review_q$i'),
              controller: _answers[i],
              minLines: 2,
              maxLines: 6,
              maxLength: 1200,
              decoration: const InputDecoration(hintText: 'Своими словами'),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          ElevatedButton(
            key: const ValueKey('review_save'),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: _save,
            child: const Text('Сохранить обзор', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  /// Варианты решения: «оставить» (без записи) и смены статуса, уместные для текущего.
  static List<({String label, String? status})> _options(LifeProcess p) => [
        (label: 'Оставить', status: null),
        if (p.status == ProcessStatus.paused) (label: 'Возобновить', status: ProcessStatus.active),
        if (p.status == ProcessStatus.active) (label: 'На паузу', status: ProcessStatus.paused),
        (label: 'Завершить', status: ProcessStatus.completed),
        (label: 'Прекратить', status: ProcessStatus.stopped),
      ];
}

const _sub = TextStyle(color: AppColors.muted, fontSize: 13);

class _Tile extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Tile({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: tileDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );
}

class _Chip extends StatelessWidget {
  final Color color;
  final String text;
  const _Chip({required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: tileDecoration(radius: 16, color: AppColors.field),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(child: Text(text, style: const TextStyle(color: Color(0xFFC8C8CC), fontSize: 13))),
          ],
        ),
      );
}
