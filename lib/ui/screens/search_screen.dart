import 'package:flutter/material.dart';

import '../../core/search.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../state/app_controller.dart';
import '../widgets/event_dialog.dart';
import '../widgets/toast.dart';
import 'bills_screen.dart';
import 'checkin_screen.dart';
import 'events_screen.dart';
import 'finance_screen.dart';

/// Поиск по всем записям: «когда я последний раз был у стоматолога?». Найденное ведёт к самой записи.
class SearchScreen extends StatefulWidget {
  final AppController controller;
  const SearchScreen({super.key, required this.controller});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  AppController get c => widget.controller;
  final _query = TextEditingController();
  String? _kind; // фильтр по виду записи; null — всё

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _open(SearchHit h) async {
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    switch (h.kind) {
      case SearchKind.event:
        final e = c.allEvents.where((x) => x.id == h.refId).firstOrNull;
        if (e == null) return;
        final d = await showEventDialog(context, now: c.now, goals: c.goals, processes: c.processes, initial: e);
        if (d == null || !mounted) return;
        final id = c.reviseEvent(e.id,
            title: d.title, dimensions: d.dimensions, kind: d.kind, at: d.at, note: d.note, cost: d.cost, goalIds: d.goalIds, processIds: d.processIds);
        showToast(context, id == null ? 'Не удалось сохранить новую версию' : 'Сохранена новая версия');
      case SearchKind.transaction:
        final t = c.transactions.where((x) => x.id == h.refId).firstOrNull;
        if (t != null) await showTransactionDialog(context, c, existing: t);
      case SearchKind.checkIn:
        push(CheckInScreen(controller: c, day: DateTime.parse(h.refId)));
      case SearchKind.process:
        push(EventsScreen(controller: c, processId: h.refId));
      case SearchKind.goal:
        push(EventsScreen(controller: c, goalId: h.refId));
      case SearchKind.bill:
        push(BillsScreen(controller: c));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.panel,
        elevation: 0,
        titleSpacing: 0,
        title: TextField(
          key: const ValueKey('search_field'),
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Поиск по записям',
            border: InputBorder.none,
            filled: false,
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Очистить',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _query.clear();
                      _kind = null;
                    }),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
      body: ListenableBuilder(listenable: c, builder: (context, _) => _results()),
    );
  }

  Widget _results() {
    final q = _query.text;
    if (searchTokens(q).isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Ищутся слова в событиях и их заметках, операциях, отметках дня и метках, процессах, целях, достижениях и счетах. '
          'Несколько слов — должны встретиться все. Число ищет ещё и суммы.',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
      );
    }
    final all = c.search(q);
    final counts = <String, int>{};
    for (final h in all) {
      counts[h.kind] = (counts[h.kind] ?? 0) + 1;
    }
    final kind = counts.containsKey(_kind) ? _kind : null;
    final hits = kind == null ? all : [for (final h in all) if (h.kind == kind) h];
    final tokens = searchTokens(q);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          all.isEmpty ? 'Ничего не нашлось' : 'Найдено: ${all.length}${all.length >= searchLimit ? ' (показаны первые $searchLimit)' : ''}',
          key: const ValueKey('search_count'),
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        if (counts.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ChoiceChip(label: const Text('Всё'), selected: kind == null, onSelected: (_) => setState(() => _kind = null)),
              for (final k in SearchKind.labels.keys)
                if (counts[k] != null)
                  ChoiceChip(
                    key: ValueKey('search_kind_$k'),
                    label: Text('${SearchKind.labels[k]} · ${counts[k]}'),
                    selected: kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        for (final h in hits) _tile(h, tokens),
      ],
    );
  }

  Widget _tile(SearchHit h, List<String> tokens) {
    final meta = [SearchKind.labels[h.kind]!, if (h.at != null) fmtDate(h.at!), if (h.voided) 'отменено'].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('hit_${h.kind}_${h.refId}'),
          onTap: h.kind == SearchKind.achievement ? null : () => _open(h),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meta, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 2),
                _highlighted(h.title.isEmpty ? '—' : h.title, tokens, const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                if (h.snippet.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  _highlighted(h.snippet, tokens, const TextStyle(color: AppColors.muted, fontSize: 13), maxLines: 2),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Текст с выделенными словами запроса (жирным, без цвета — цвет только со смыслом).
  static Widget _highlighted(String text, List<String> tokens, TextStyle style, {int maxLines = 1}) {
    final n = normalizeSearch(text);
    final marks = List<bool>.filled(text.length, false);
    for (final t in tokens) {
      for (var i = n.indexOf(t); i >= 0; i = n.indexOf(t, i + 1)) {
        for (var k = i; k < i + t.length && k < marks.length; k++) {
          marks[k] = true;
        }
      }
    }
    final spans = <TextSpan>[];
    var i = 0;
    while (i < text.length) {
      var j = i;
      while (j < text.length && marks[j] == marks[i]) {
        j++;
      }
      spans.add(TextSpan(
        text: text.substring(i, j),
        style: marks[i] ? const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text, decoration: TextDecoration.underline) : null,
      ));
      i = j;
    }
    return Text.rich(TextSpan(style: style, children: spans), maxLines: maxLines, overflow: TextOverflow.ellipsis);
  }
}
