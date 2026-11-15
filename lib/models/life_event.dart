// Ядро LIFE OS: событие жизни. Чистый Dart, без Flutter.
//
// Событие — факт, который произошёл: действие, веха, решение, изменение состояния или наблюдение.
// Оно относится к одному или нескольким измерениям (BODY / MIND / MATERIAL), может указывать
// затраченные ресурсы, вести к целям и ссылаться на записи других журналов (подход, операция, достижение).
//
// Целостность истории:
// * событие не редактируется «на месте» — правка создаёт новую версию ([supersedesId] → предыдущая);
// * «отмена» помечает событие ([voidedAt]), но не удаляет его;
// * физическое удаление — только явное действие пользователя (право владельца данных).

const int _maxMs = 8640000000000000;

String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
int? _int(Object? v) => v is num && v.isFinite && v == v.roundToDouble() ? v.toInt() : null;
DateTime? _time(Object? v) {
  final ms = _int(v);
  if (ms == null || ms.abs() > _maxMs) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms);
}

/// Измерения жизни.
class LifeDimension {
  static const body = 'body';
  static const mind = 'mind';
  static const material = 'material';

  static const all = [body, mind, material];
  static const labels = {body: 'Тело', mind: 'Разум', material: 'Материальное'};
  static bool isValid(String d) => labels.containsKey(d);
}

/// Вид события.
class LifeEventKind {
  static const action = 'action'; // действие, практика: тренировка, занятие, работа
  static const milestone = 'milestone'; // веха: результат, достижение, завершение
  static const decision = 'decision'; // решение и его основания
  static const change = 'change'; // изменение положения: переезд, новая работа, травма
  static const observation = 'observation'; // наблюдение о состоянии

  static const labels = {
    action: 'Действие',
    milestone: 'Веха',
    decision: 'Решение',
    change: 'Изменение',
    observation: 'Наблюдение',
  };
  static bool isValid(String k) => labels.containsKey(k);
}

/// Откуда взялось событие (прозрачность происхождения данных).
class EventSource {
  static const manual = 'manual';
  static const health = 'health';
  static const auto = 'auto';
  static const _all = {manual, health, auto};
  static bool isValid(String s) => _all.contains(s);
}

/// Затраты ресурсов. null — «не указано», это НЕ ноль: статистика считает такие события отдельно.
class ResourceCost {
  static const maxMinutes = 7 * 24 * 60; // одно событие — не больше недели
  static const minEnergy = 1;
  static const maxEnergy = 5;

  final int? minutes; // время
  final int? money; // деньги, ₽ (затрачено)
  final int? energy; // энергия, субъективная шкала 1–5 (не мера, а оценка)

  const ResourceCost({this.minutes, this.money, this.energy});

  static const none = ResourceCost();

  bool get isEmpty => minutes == null && money == null && energy == null;

  bool get isValid =>
      (minutes == null || (minutes! >= 0 && minutes! <= maxMinutes)) &&
      (money == null || money! >= 0) &&
      (energy == null || (energy! >= minEnergy && energy! <= maxEnergy));

  Map<String, dynamic> toJson() => {
        if (minutes != null) 'min': minutes,
        if (money != null) 'rub': money,
        if (energy != null) 'en': energy,
      };

  /// null — поле есть, но значение недопустимо (молча терять затраты нельзя).
  static ResourceCost? tryFromJson(Object? raw) {
    if (raw == null) return none;
    if (raw is! Map) return null;
    final c = ResourceCost(
      minutes: raw['min'] == null ? null : _int(raw['min']) ?? -1,
      money: raw['rub'] == null ? null : _int(raw['rub']) ?? -1,
      energy: raw['en'] == null ? null : _int(raw['en']) ?? -1,
    );
    return c.isValid ? c : null;
  }

  @override
  bool operator ==(Object other) =>
      other is ResourceCost && other.minutes == minutes && other.money == money && other.energy == energy;

  @override
  int get hashCode => Object.hash(minutes, money, energy);
}

/// Ссылка на запись другого журнала — доказательство события.
class EventRef {
  static const workoutSet = 'set';
  static const transaction = 'tx';
  static const achievement = 'ach';
  static const _types = {workoutSet, transaction, achievement};

  final String type;
  final String id;
  const EventRef(this.type, this.id);

  static bool isValidType(String t) => _types.contains(t);

  Map<String, dynamic> toJson() => {'type': type, 'id': id};

  static EventRef? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    final id = _str(raw['id']);
    if (type is! String || !isValidType(type) || id == null) return null;
    return EventRef(type, id);
  }

  @override
  bool operator ==(Object other) => other is EventRef && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}

class LifeEvent {
  static const maxTitle = 200;
  static const maxNote = 4000;
  static const maxLinks = 50;

  final String id;
  final DateTime at; // когда произошло
  final DateTime recordedAt; // когда записано (свидетельство: задним числом или сразу)
  final List<String> dimensions; // непустой, без повторов, в порядке LifeDimension.all
  final String kind;
  final String title;
  final String note;
  final ResourceCost cost;
  final List<String> goalIds; // цели, к которым ведёт событие (цель может быть уже удалена — история остаётся)
  final List<String> processIds; // процессы, в которые вложено событие (так же: удалённый процесс не стирает историю)
  final List<EventRef> refs;
  final String source;
  final String? supersedesId; // это событие — новая версия события [supersedesId]
  final DateTime? voidedAt; // отменено пользователем (запись сохраняется в истории)

  LifeEvent({
    required this.id,
    required this.at,
    required this.recordedAt,
    required Iterable<String> dimensions,
    required this.kind,
    required this.title,
    this.note = '',
    this.cost = ResourceCost.none,
    Iterable<String> goalIds = const [],
    Iterable<String> processIds = const [],
    Iterable<EventRef> refs = const [],
    this.source = EventSource.manual,
    this.supersedesId,
    this.voidedAt,
  })  : dimensions = List.unmodifiable(normalizeDimensions(dimensions)),
        goalIds = List.unmodifiable(goalIds.toSet()),
        processIds = List.unmodifiable(processIds.toSet()),
        refs = List.unmodifiable(refs.toSet());

  /// Порядок по LifeDimension.all, без повторов и неизвестных значений.
  static List<String> normalizeDimensions(Iterable<String> ds) {
    final s = ds.toSet();
    return [for (final d in LifeDimension.all) if (s.contains(d)) d];
  }

  bool get isVoided => voidedAt != null;

  bool touches(String dimension) => dimensions.contains(dimension);

  /// Проверка инвариантов (контроллер не создаёт, а строгий импорт не принимает событие, не прошедшее её).
  bool get isValid =>
      _str(id) != null &&
      dimensions.isNotEmpty &&
      LifeEventKind.isValid(kind) &&
      title.trim().isNotEmpty &&
      title.length <= maxTitle &&
      note.length <= maxNote &&
      cost.isValid &&
      goalIds.length <= maxLinks &&
      refs.length <= maxLinks &&
      goalIds.every((g) => _str(g) != null) &&
      processIds.length <= maxLinks &&
      processIds.every((p) => _str(p) != null) &&
      EventSource.isValid(source) &&
      supersedesId != id;

  LifeEvent copyWith({DateTime? voidedAt, bool clearVoided = false}) => LifeEvent(
        id: id,
        at: at,
        recordedAt: recordedAt,
        dimensions: dimensions,
        kind: kind,
        title: title,
        note: note,
        cost: cost,
        goalIds: goalIds,
        processIds: processIds,
        refs: refs,
        source: source,
        supersedesId: supersedesId,
        voidedAt: clearVoided ? null : (voidedAt ?? this.voidedAt),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        't': at.millisecondsSinceEpoch,
        'rt': recordedAt.millisecondsSinceEpoch,
        'dims': dimensions,
        'kind': kind,
        'title': title,
        if (note.isNotEmpty) 'note': note,
        if (!cost.isEmpty) 'cost': cost.toJson(),
        if (goalIds.isNotEmpty) 'goals': goalIds,
        if (processIds.isNotEmpty) 'procs': processIds,
        if (refs.isNotEmpty) 'refs': refs.map((r) => r.toJson()).toList(),
        'src': source,
        if (supersedesId != null) 'sup': supersedesId,
        if (voidedAt != null) 'void': voidedAt!.millisecondsSinceEpoch,
      };

  factory LifeEvent.fromJson(Map<String, dynamic> j) =>
      tryFromJson(j) ?? (throw const FormatException('LifeEvent'));

  /// null — запись нарушает инварианты. Частично битую запись не «чиним» молча: это была бы подмена истории.
  static LifeEvent? tryFromJson(Map<String, dynamic> j) {
    final id = _str(j['id']);
    final at = _time(j['t']);
    final rt = j['rt'] == null ? at : _time(j['rt']);
    final dims = j['dims'];
    final kind = j['kind'];
    final title = j['title'];
    final note = j['note'] ?? '';
    final cost = ResourceCost.tryFromJson(j['cost']);
    final goals = j['goals'] ?? const [];
    final procs = j['procs'] ?? const [];
    final refsRaw = j['refs'] ?? const [];
    final src = j['src'] ?? EventSource.manual;
    final sup = j['sup'];
    final voidRaw = j['void'];
    if (id == null || at == null || rt == null || cost == null) return null;
    if (dims is! List || dims.isEmpty || !dims.every((d) => d is String && LifeDimension.isValid(d))) return null;
    if (kind is! String || title is! String || note is! String || src is! String) return null;
    if (goals is! List || !goals.every((g) => _str(g) != null)) return null;
    if (procs is! List || !procs.every((p) => _str(p) != null)) return null;
    if (refsRaw is! List) return null;
    final refs = <EventRef>[];
    for (final r in refsRaw) {
      final ref = EventRef.tryFromJson(r);
      if (ref == null) return null;
      refs.add(ref);
    }
    if (sup != null && _str(sup) == null) return null;
    final voided = voidRaw == null ? null : _time(voidRaw);
    if (voidRaw != null && voided == null) return null;
    final e = LifeEvent(
      id: id,
      at: at,
      recordedAt: rt,
      dimensions: dims.cast<String>(),
      kind: kind,
      title: title,
      note: note,
      cost: cost,
      goalIds: goals.cast<String>(),
      processIds: procs.cast<String>(),
      refs: refs,
      source: src,
      supersedesId: sup as String?,
      voidedAt: voided,
    );
    return e.isValid ? e : null;
  }
}

/// Проверка целостности журнала событий как целого: уникальные id, версии ссылаются на существующие
/// события, у события не больше одной следующей версии, нет циклов. null — всё в порядке, иначе описание.
String? eventJournalProblem(List<LifeEvent> events) {
  final byId = <String, LifeEvent>{};
  for (final e in events) {
    if (byId.containsKey(e.id)) return 'повторяющийся id "${e.id}"';
    byId[e.id] = e;
  }
  final next = <String, String>{};
  for (final e in events) {
    final sup = e.supersedesId;
    if (sup == null) continue;
    if (!byId.containsKey(sup)) return 'событие "${e.id}" — версия несуществующего "$sup"';
    if (next.containsKey(sup)) return 'у события "$sup" несколько новых версий';
    next[sup] = e.id;
  }
  for (final e in events) {
    var cur = e.supersedesId;
    var steps = 0;
    while (cur != null) {
      if (cur == e.id || ++steps > events.length) return 'цикл версий у события "${e.id}"';
      cur = byId[cur]?.supersedesId;
    }
  }
  return null;
}
