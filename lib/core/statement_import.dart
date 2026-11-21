import 'utils.dart';

/// Разбор банковской выписки в CSV. Чистая логика без Flutter.
///
/// Банки выгружают по-разному: разделитель «;» или «,», дата «18.11.2026» или «2026-11-18», сумма со знаком
/// или отдельными колонками «приход / расход», «1 234,56» или «1,234.56». Колонки распознаются по названиям,
/// а человек может их поправить. Ничего не угадывается молча: каждая нераспознанная строка — в списке
/// с причиной, а не выброшена.

class CsvTable {
  final List<String> header;
  final List<List<String>> rows;
  final int headerLine; // номер строки заголовка в файле (с 1)
  final List<int> rowLines; // номер строки файла для каждой из [rows]
  const CsvTable(this.header, this.rows, this.headerLine, [this.rowLines = const []]);
}

/// Какая колонка что значит. Сумма — либо [amount] со знаком, либо пара [income] / [expense].
class ColumnMapping {
  final int? date;
  final int? amount;
  final int? income;
  final int? expense;
  final int? note;
  const ColumnMapping({this.date, this.amount, this.income, this.expense, this.note});

  bool get isComplete => date != null && (amount != null || income != null || expense != null);
}

class StatementRow {
  final int line; // строка в файле (с 1)
  final DateTime at;
  final int signed; // > 0 — поступление, < 0 — списание; в целых единицах валюты
  final String note;
  const StatementRow(this.line, this.at, this.signed, this.note);

  /// Отпечаток для поиска уже загруженного: день, сумма со знаком, описание.
  String get fingerprint => statementFingerprint(at, signed, note);
}

String statementFingerprint(DateTime at, int signed, String note) => '${dayKey(at)}|$signed|${note.trim().toLowerCase()}';

class RejectedRow {
  final int line;
  final String reason;
  const RejectedRow(this.line, this.reason);
}

class ParsedStatement {
  final List<StatementRow> rows;
  final List<RejectedRow> rejected;
  const ParsedStatement(this.rows, this.rejected);
}

// ---------------- CSV ----------------

/// Разделитель — тот из «;», «,», табуляции, которого больше всего в первых строках вне кавычек.
String detectDelimiter(String text) {
  final sample = text.split('\n').take(20).join('\n');
  var best = ';';
  var bestCount = -1;
  for (final d in const [';', ',', '\t']) {
    var n = 0, quoted = false;
    for (final ch in sample.split('')) {
      if (ch == '"') quoted = !quoted;
      if (!quoted && ch == d) n++;
    }
    if (n > bestCount) {
      best = d;
      bestCount = n;
    }
  }
  return best;
}

/// Строки CSV: кавычки, «""» внутри кавычек, переносы строк внутри кавычек. Каждой записи — номер её первой строки.
List<(int, List<String>)> parseCsvRecords(String text, String delimiter) {
  final s = text.startsWith('﻿') ? text.substring(1) : text;
  final out = <(int, List<String>)>[];
  var field = StringBuffer();
  var record = <String>[];
  var quoted = false;
  var line = 1, recordLine = 1;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        if (ch == '\n') line++;
        field.write(ch);
      }
      continue;
    }
    if (ch == '"') {
      quoted = true;
    } else if (ch == delimiter) {
      record.add(field.toString());
      field = StringBuffer();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
      record.add(field.toString());
      field = StringBuffer();
      if (record.any((f) => f.trim().isNotEmpty)) out.add((recordLine, record));
      record = <String>[];
      line++;
      recordLine = line;
    } else {
      field.write(ch);
    }
  }
  record.add(field.toString());
  if (record.any((f) => f.trim().isNotEmpty)) out.add((recordLine, record));
  return out;
}

const _dateNames = ['дата операции', 'дата проводки', 'дата', 'date', 'posted', 'transaction date'];
const _amountNames = ['сумма операции', 'сумма в валюте счета', 'сумма платежа', 'сумма', 'amount'];
const _incomeNames = ['приход', 'поступление', 'зачисление', 'credit', 'кредит'];
const _expenseNames = ['расход', 'списание', 'debit', 'дебет'];
const _noteNames = ['описание', 'назначение', 'комментарий', 'получатель', 'контрагент', 'description', 'details', 'merchant', 'payee', 'категория', 'category'];

int? _find(List<String> header, List<String> names) {
  final h = [for (final x in header) x.trim().toLowerCase()];
  for (final n in names) {
    for (var i = 0; i < h.length; i++) {
      if (h[i] == n) return i;
    }
  }
  for (final n in names) {
    for (var i = 0; i < h.length; i++) {
      if (h[i].contains(n)) return i;
    }
  }
  return null;
}

/// Таблица выписки: заголовок — первая из первых 20 строк, где нашлась колонка даты (у банков бывает
/// шапка с номером счета над таблицей). Не нашлась — первая строка.
CsvTable parseCsvTable(String text) {
  final records = parseCsvRecords(text, detectDelimiter(text));
  if (records.isEmpty) return const CsvTable([], [], 0);
  var h = 0;
  for (var i = 0; i < records.length && i < 20; i++) {
    if (_find(records[i].$2, _dateNames) != null) {
      h = i;
      break;
    }
  }
  final data = records.skip(h + 1);
  return CsvTable(records[h].$2.map((x) => x.trim()).toList(), [for (final r in data) r.$2], records[h].$1, [for (final r in data) r.$1]);
}

ColumnMapping detectMapping(List<String> header) {
  final amount = _find(header, _amountNames);
  final income = amount == null ? _find(header, _incomeNames) : null;
  final expense = amount == null ? _find(header, _expenseNames) : null;
  final used = {amount, income, expense};
  var note = _find(header, _noteNames);
  if (used.contains(note)) note = null;
  return ColumnMapping(date: _find(header, _dateNames), amount: amount, income: income, expense: expense, note: note);
}

// ---------------- значения ----------------

final _dmy = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})(?:[ T,]+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$');
final _ymd = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T]+(\d{1,2}):(\d{2})(?::(\d{2}))?)?');

/// Дата операции; без времени — полдень (чтобы сдвиг часового пояса не переносил операцию на другой день).
DateTime? parseStatementDate(String raw) {
  final s = raw.trim();
  int? i(String? x) => x == null ? null : int.tryParse(x);
  DateTime? build(int y, int m, int d, int? hh, int? mm, int? ss) {
    if (y < 100) y += 2000;
    final t = DateTime(y, m, d, hh ?? 12, mm ?? 0, ss ?? 0);
    if (t.year != y || t.month != m || t.day != d || (hh ?? 0) > 23 || (mm ?? 0) > 59) return null;
    return t;
  }

  final a = _dmy.firstMatch(s);
  if (a != null) return build(i(a[3])!, i(a[2])!, i(a[1])!, i(a[4]), i(a[5]), i(a[6]));
  final b = _ymd.firstMatch(s);
  if (b != null) return build(i(b[1])!, i(b[2])!, i(b[3])!, i(b[4]), i(b[5]), i(b[6]));
  return null;
}

/// Сумма в целых единицах валюты (копейки округляются). «−1 234,56 ₽» → -1235; «1,234.56» → 1235. null — не число.
int? parseStatementAmount(String raw) {
  var s = raw.trim().replaceAll(' ', '').replaceAll(' ', '').replaceAll(' ', '').replaceAll('−', '-').replaceAll('–', '-');
  final neg = s.startsWith('-') || (s.startsWith('(') && s.endsWith(')'));
  s = s.replaceAll(RegExp(r'[^0-9.,]'), '');
  if (s.isEmpty) return null;
  final lastComma = s.lastIndexOf(','), lastDot = s.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    // десятичный разделитель — последний из двух
    s = lastComma > lastDot ? s.replaceAll('.', '').replaceAll(',', '.') : s.replaceAll(',', '');
  } else if (lastComma >= 0) {
    final decimals = s.length - lastComma - 1;
    s = ','.allMatches(s).length == 1 && decimals <= 2 ? s.replaceAll(',', '.') : s.replaceAll(',', '');
  } else if (lastDot >= 0) {
    // как с запятой: одна точка и до двух знаков после — копейки; три знака или несколько точек — разряды тысяч
    final decimals = s.length - lastDot - 1;
    if ('.'.allMatches(s).length > 1 || decimals == 3) s = s.replaceAll('.', '');
  }
  final v = double.tryParse(s);
  if (v == null || !v.isFinite) return null;
  final r = v.round();
  return neg ? -r : r;
}

/// Строки выписки по [mapping]. Строки в будущем, без даты, без суммы или с нулевой суммой — в [ParsedStatement.rejected].
ParsedStatement parseStatement(String text, ColumnMapping mapping, {required DateTime now}) {
  final t = parseCsvTable(text);
  final lines = t.rowLines;
  final rows = <StatementRow>[];
  final rejected = <RejectedRow>[];
  if (!mapping.isComplete) return ParsedStatement(rows, rejected);
  String cell(List<String> r, int? i) => i == null || i >= r.length ? '' : r[i];
  for (var k = 0; k < t.rows.length; k++) {
    final r = t.rows[k];
    final line = k < lines.length ? lines[k] : t.headerLine + k + 1;
    final at = parseStatementDate(cell(r, mapping.date));
    if (at == null) {
      rejected.add(RejectedRow(line, 'не распознана дата «${cell(r, mapping.date).trim()}»'));
      continue;
    }
    if (at.isAfter(now.add(const Duration(days: 1)))) {
      rejected.add(RejectedRow(line, 'дата в будущем'));
      continue;
    }
    int? signed;
    if (mapping.amount != null) {
      signed = parseStatementAmount(cell(r, mapping.amount));
    } else {
      final inc = cell(r, mapping.income).trim().isEmpty ? null : parseStatementAmount(cell(r, mapping.income));
      final exp = cell(r, mapping.expense).trim().isEmpty ? null : parseStatementAmount(cell(r, mapping.expense));
      if (inc != null || exp != null) signed = (inc?.abs() ?? 0) - (exp?.abs() ?? 0);
    }
    if (signed == null) {
      rejected.add(RejectedRow(line, 'не распознана сумма'));
      continue;
    }
    if (signed == 0) {
      rejected.add(RejectedRow(line, 'нулевая сумма'));
      continue;
    }
    final note = cell(r, mapping.note).trim();
    rows.add(StatementRow(line, at, signed, note.length > 500 ? note.substring(0, 500) : note));
  }
  return ParsedStatement(rows, rejected);
}

/// Делит строки на новые и уже загруженные. [existing] — отпечатки операций из прежних импортов. Учитывается
/// количество: две одинаковые покупки кофе в один день — две операции, если раньше была загружена одна.
({List<StatementRow> fresh, List<StatementRow> duplicates}) splitDuplicates(List<StatementRow> rows, Iterable<String> existing) {
  final left = <String, int>{};
  for (final f in existing) {
    left[f] = (left[f] ?? 0) + 1;
  }
  final fresh = <StatementRow>[], dup = <StatementRow>[];
  for (final r in rows) {
    final n = left[r.fingerprint] ?? 0;
    if (n > 0) {
      left[r.fingerprint] = n - 1;
      dup.add(r);
    } else {
      fresh.add(r);
    }
  }
  return (fresh: fresh, duplicates: dup);
}
