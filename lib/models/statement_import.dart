// Импорт банковской выписки: запись о том, что, когда и сколько было загружено. Чистый Dart, без Flutter.
//
// Каждая импортированная операция ссылается на свой импорт (`MoneyTx.importId`) — происхождение видно.
// Отмена импорта удаляет его операции (явное действие с подтверждением), а сама запись остаётся
// с пометкой `undoneAt`: история того, что загружалось, не теряется.

class StatementImport {
  static const maxName = 120;

  final String id;
  final DateTime at; // когда импортировано
  final String name; // как назвал человек: «Тинькофф, октябрь»
  final int added; // сколько операций добавлено
  final int duplicates; // пропущено как уже загруженные раньше
  final int rejected; // строк не распознано
  DateTime? undoneAt;

  StatementImport({
    required this.id,
    required this.at,
    required this.name,
    required this.added,
    this.duplicates = 0,
    this.rejected = 0,
    this.undoneAt,
  });

  bool get isValid =>
      id.trim().isNotEmpty && name.trim().isNotEmpty && name.length <= maxName && added >= 0 && duplicates >= 0 && rejected >= 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        't': at.millisecondsSinceEpoch,
        'name': name,
        'add': added,
        'dup': duplicates,
        'bad': rejected,
        if (undoneAt != null) 'undo': undoneAt!.millisecondsSinceEpoch,
      };

  factory StatementImport.fromJson(Map<String, dynamic> j) => tryFromJson(j) ?? (throw const FormatException('StatementImport'));

  static StatementImport? tryFromJson(Map<String, dynamic> j) {
    DateTime? t(Object? v) => v is num && v.isFinite && v == v.roundToDouble() ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    int? n(Object? v) => v is num && v.isFinite && v == v.roundToDouble() ? v.toInt() : null;
    final id = j['id'], name = j['name'], at = t(j['t']), add = n(j['add']), dup = n(j['dup'] ?? 0), bad = n(j['bad'] ?? 0);
    if (id is! String || name is! String || at == null || add == null || dup == null || bad == null) return null;
    if (j['undo'] != null && t(j['undo']) == null) return null;
    final x = StatementImport(id: id, at: at, name: name, added: add, duplicates: dup, rejected: bad, undoneAt: t(j['undo']));
    return x.isValid ? x : null;
  }
}
