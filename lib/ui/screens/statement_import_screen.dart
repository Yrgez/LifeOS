import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/currency.dart';
import '../../core/finance_categories.dart';
import '../../core/statement_import.dart';
import '../../core/text_decoding.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/file_selector_source.dart';
import '../../data/file_source.dart';
import '../../state/app_controller.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';
import '../widgets/toast.dart';

/// Импорт банковской выписки (CSV): файл или текст из буфера → колонки → предпросмотр → импорт.
/// Внизу — прежние импорты с отменой. Файл читается только в память и никуда не отправляется.
class StatementImportScreen extends StatefulWidget {
  /// Больше — точно не выписка за разумный период (и не стоит держать в памяти).
  static const maxFileBytes = 5 * 1024 * 1024;

  final AppController controller;
  final FileSource files;
  const StatementImportScreen({super.key, required this.controller, this.files = const FileSelectorSource(maxBytes: maxFileBytes)});

  @override
  State<StatementImportScreen> createState() => _StatementImportScreenState();
}

class _StatementImportScreenState extends State<StatementImportScreen> {
  AppController get c => widget.controller;
  final _text = TextEditingController();
  final _name = TextEditingController();
  ColumnMapping _mapping = const ColumnMapping();
  List<String> _header = const [];
  String _expenseCat = 'other_exp';
  String _incomeCat = 'other_inc';
  bool _affectsNetWorth = false;
  String? _source; // «файл.csv · Windows-1251» или «из буфера обмена»

  @override
  void dispose() {
    _text.dispose();
    _name.dispose();
    super.dispose();
  }

  void _analyze() {
    final t = parseCsvTable(_text.text);
    setState(() {
      _header = t.header;
      _mapping = detectMapping(t.header);
    });
  }

  Future<void> _pickFile() async {
    PickedFile? f;
    try {
      f = await widget.files.pickFile();
    } on FileTooLargeException {
      if (mounted) showToast(context, 'Файл больше 5 МБ — выгрузите выписку за меньший период');
      return;
    } catch (_) {
      if (mounted) showToast(context, 'Не удалось открыть файл. Попробуйте ещё раз или вставьте текст из буфера');
      return;
    }
    if (f == null || !mounted) return;
    if (f.bytes.length > StatementImportScreen.maxFileBytes) {
      showToast(context, 'Файл больше 5 МБ — выгрузите выписку за меньший период');
      return;
    }
    final d = decodeStatementBytes(f.bytes);
    if (d == null) {
      showToast(context, 'Это не текстовый CSV (например, Excel). Сохраните выписку в банке как CSV');
      return;
    }
    _text.text = d.text;
    final dot = f.name.lastIndexOf('.');
    _name.text = (dot > 0 ? f.name.substring(0, dot) : f.name).trim();
    if (_name.text.isEmpty) _name.text = 'Выписка ${fmtDate(c.now)}';
    _source = '${f.name} · ${d.encoding}';
    _analyze();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final s = data?.text ?? '';
    if (s.trim().isEmpty) {
      if (mounted) showToast(context, 'Буфер обмена пуст: скопируйте текст выписки (CSV)');
      return;
    }
    _text.text = s;
    if (_name.text.trim().isEmpty) _name.text = 'Выписка ${fmtDate(c.now)}';
    _source = 'из буфера обмена';
    _analyze();
  }

  void _import() {
    final id = c.importStatement(_text.text, _mapping,
        name: _name.text, expenseCategory: _expenseCat, incomeCategory: _incomeCat, affectsNetWorth: _affectsNetWorth);
    if (id == null) {
      showToast(context, 'Импорт не выполнен: проверьте колонки и название');
      return;
    }
    final imp = c.statementImports.firstWhere((x) => x.id == id);
    showToast(context, 'Добавлено операций: ${imp.added}');
    setState(() {
      _text.clear();
      _source = null;
      _header = const [];
      _mapping = const ColumnMapping();
    });
  }

  /// Правило из частого описания: «Пятёрочка» → выбранная категория. Применяется к этому и будущим импортам.
  Future<void> _ruleFor(String pattern) async {
    final r = await showFormDialog(
      context,
      title: 'Правило для «$pattern»',
      actionLabel: 'Запомнить',
      accent: AppColors.accent,
      fields: [
        FieldSpec('p', 'Если описание содержит', initial: pattern),
        FieldSpec('c', 'Категория', initial: 'food', options: {
          for (final x in pickableFinCategories()) x.id: '${x.isIncome ? 'Доход' : 'Расход'} • ${x.name}',
        }),
      ],
      validate: (v) => v['p']!.trim().length >= 2,
    );
    if (r == null || !mounted) return;
    if (c.addImportRule(r['p']!, r['c']!) == null) {
      showToast(context, 'Правило не сохранено');
      return;
    }
    setState(() {});
  }

  Future<void> _undo(String id, String name, int added) async {
    final ok = await confirmDialog(context,
        title: 'Отменить импорт?',
        message: 'Операции импорта «$name» ($added) будут удалены из журнала. Запись о самом импорте останется.',
        confirmLabel: 'Отменить импорт',
        danger: true);
    if (!ok || !mounted) return;
    final n = c.undoImport(id);
    if (n != null) showToast(context, 'Удалено операций: $n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Импорт выписки'), backgroundColor: AppColors.panel, elevation: 0),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Text(
              'Выгрузите выписку из банка в CSV и выберите файл. Уже загруженные раньше операции не повторятся. '
              'Файл читается только на телефоне.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('import_file'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(46)),
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Выбрать файл'),
            ),
            TextButton.icon(
              key: const ValueKey('import_paste'),
              onPressed: _paste,
              icon: const Icon(Icons.content_paste, size: 18),
              label: const Text('Или вставить текст из буфера'),
            ),
            if (_source != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Источник: $_source', key: const ValueKey('import_source'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
            TextField(
              key: const ValueKey('import_text'),
              controller: _text,
              minLines: 3,
              maxLines: 6,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(hintText: 'Дата; Сумма; Описание\n18.11.2026; -450,00; Кофейня'),
              onChanged: (_) {
                _source = null; // текст правят руками — источник уже не файл
                _analyze();
              },
            ),
            if (_header.isNotEmpty) ..._mappingSection(),
            if (_mapping.isComplete) ..._previewSection(),
            ..._history(),
          ],
        ),
      ),
    );
  }

  // ---------------- колонки ----------------

  Widget _columnPicker(String label, int? value, ValueChanged<int?> onChanged, {Key? key}) => Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
          Expanded(
            child: DropdownButton<int?>(
              key: key,
              isExpanded: true,
              value: value != null && value < _header.length ? value : null,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('—')),
                for (var i = 0; i < _header.length; i++)
                  DropdownMenuItem<int?>(value: i, child: Text(_header[i].isEmpty ? 'колонка ${i + 1}' : _header[i], overflow: TextOverflow.ellipsis)),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      );

  List<Widget> _mappingSection() => [
        const SizedBox(height: 16),
        const Text('КОЛОНКИ', style: _caption),
        const Text('Распознаны по названиям — поправьте, если нужно.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        _columnPicker('Дата', _mapping.date, (v) => setState(() => _mapping = ColumnMapping(date: v, amount: _mapping.amount, income: _mapping.income, expense: _mapping.expense, note: _mapping.note)),
            key: const ValueKey('map_date')),
        _columnPicker('Сумма (±)', _mapping.amount,
            (v) => setState(() => _mapping = ColumnMapping(date: _mapping.date, amount: v, income: v == null ? _mapping.income : null, expense: v == null ? _mapping.expense : null, note: _mapping.note)),
            key: const ValueKey('map_amount')),
        if (_mapping.amount == null) ...[
          _columnPicker('Поступление', _mapping.income,
              (v) => setState(() => _mapping = ColumnMapping(date: _mapping.date, income: v, expense: _mapping.expense, note: _mapping.note))),
          _columnPicker('Списание', _mapping.expense,
              (v) => setState(() => _mapping = ColumnMapping(date: _mapping.date, income: _mapping.income, expense: v, note: _mapping.note))),
        ],
        _columnPicker('Описание', _mapping.note,
            (v) => setState(() => _mapping = ColumnMapping(date: _mapping.date, amount: _mapping.amount, income: _mapping.income, expense: _mapping.expense, note: v))),
        if (!_mapping.isComplete)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Выберите колонку даты и суммы.', style: TextStyle(color: AppColors.text, fontSize: 12)),
          ),
      ];

  // ---------------- предпросмотр ----------------

  List<Widget> _previewSection() {
    final p = c.previewStatement(_text.text, _mapping);
    final income = p.fresh.where((r) => r.signed > 0).fold<int>(0, (a, r) => a + r.signed);
    final expense = p.fresh.where((r) => r.signed < 0).fold<int>(0, (a, r) => a - r.signed);
    final fits = p.fresh.length <= c.transactionCapacityLeft;
    final expCats = pickableFinCategories(income: false);
    final incCats = pickableFinCategories(income: true);
    final ruleHits = c.statementRuleHits(p.fresh);
    final unmatched = c.statementUnmatched(p.fresh);
    return [
      const SizedBox(height: 16),
      const Text('ПРЕДПРОСМОТР', style: _caption),
      const SizedBox(height: 6),
      Container(
        key: const ValueKey('import_preview'),
        padding: const EdgeInsets.all(14),
        decoration: tileDecoration(radius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Новых операций: ${p.fresh.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (p.fresh.isNotEmpty)
              Text('поступления ${fmtCur(income)} · списания ${fmtCur(expense)}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            if (p.duplicates.isNotEmpty)
              Text('Уже загружены раньше — пропускаются: ${p.duplicates.length}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            if (p.parsed.rejected.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Не распознано строк: ${p.parsed.rejected.length}', style: const TextStyle(color: AppColors.text, fontSize: 13)),
              for (final r in p.parsed.rejected.take(5))
                Text('строка ${r.line}: ${r.reason}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              if (p.parsed.rejected.length > 5) Text('…и ещё ${p.parsed.rejected.length - 5}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
            if (p.fresh.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final r in p.fresh.take(5))
                Text('${fmtDate(r.at)}  ${r.signed > 0 ? '+' : '−'}${fmtCur(r.signed.abs())}  ${r.note}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              if (p.fresh.length > 5) Text('…и ещё ${p.fresh.length - 5}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ],
        ),
      ),
      if (p.fresh.isNotEmpty) ...[
        const SizedBox(height: 12),
        Row(children: [
          const SizedBox(width: 110, child: Text('Списания', style: TextStyle(color: AppColors.muted, fontSize: 13))),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _expenseCat,
              items: [for (final x in expCats) DropdownMenuItem(value: x.id, child: Text(x.name))],
              onChanged: (v) => setState(() => _expenseCat = v ?? _expenseCat),
            ),
          ),
        ]),
        Row(children: [
          const SizedBox(width: 110, child: Text('Поступления', style: TextStyle(color: AppColors.muted, fontSize: 13))),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _incomeCat,
              items: [for (final x in incCats) DropdownMenuItem(value: x.id, child: Text(x.name))],
              onChanged: (v) => setState(() => _incomeCat = v ?? _incomeCat),
            ),
          ),
        ]),
        Text(
          ruleHits > 0
              ? 'По вашим правилам разберётся $ruleHits из ${p.fresh.length}; остальные — в выбранные выше категории.'
              : 'Категорию каждой операции можно поправить потом в журнале операций.',
          key: const ValueKey('import_rule_hits'),
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        if (unmatched.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('ЧАСТЫЕ ОПИСАНИЯ БЕЗ ПРАВИЛА', style: _caption),
          for (final (pattern, n) in unmatched)
            Row(
              children: [
                Expanded(child: Text('«$pattern» · $n', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                TextButton(
                  key: ValueKey('rule_for_$pattern'),
                  onPressed: () => _ruleFor(pattern),
                  child: const Text('Категория…'),
                ),
              ],
            ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _affectsNetWorth,
          onChanged: (v) => setState(() => _affectsNetWorth = v),
          title: const Text('Менять капитал', style: TextStyle(fontSize: 14)),
          subtitle: const Text('Обычно выключено: в указанном капитале прошлые траты уже учтены', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ),
        TextField(
          key: const ValueKey('import_name'),
          controller: _name,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Название импорта', hintText: 'Банк, месяц', counterText: ''),
          onChanged: (_) => setState(() {}),
        ),
        if (!fits)
          Text('Не помещается в журнал: свободно ${c.transactionCapacityLeft}', style: const TextStyle(color: AppColors.text, fontSize: 12)),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('import_run'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)),
          onPressed: fits && _name.text.trim().isNotEmpty ? _import : null,
          child: Text('Импортировать ${p.fresh.length}'),
        ),
      ],
    ];
  }

  // ---------------- история ----------------

  List<Widget> _history() {
    final list = c.statementImports.reversed.toList();
    if (list.isEmpty) return const [];
    return [
      const SizedBox(height: 24),
      const Text('ПРЕЖНИЕ ИМПОРТЫ', style: _caption),
      const SizedBox(height: 6),
      for (final x in list)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: tileDecoration(radius: 20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(x.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      [
                        '${fmtDate(x.at)} · добавлено ${x.added}',
                        if (x.duplicates > 0) 'повторов ${x.duplicates}',
                        if (x.rejected > 0) 'не распознано ${x.rejected}',
                        if (x.undoneAt != null) 'отменён ${fmtDate(x.undoneAt!)}',
                      ].join(' · '),
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (x.undoneAt == null)
                IconButton(
                  key: ValueKey('import_undo_${x.id}'),
                  tooltip: 'Отменить импорт',
                  icon: const Icon(Icons.undo, color: AppColors.muted, size: 20),
                  onPressed: () => _undo(x.id, x.name, x.added),
                ),
            ],
          ),
        ),
    ];
  }
}

const _caption = TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8);
