import '../models/life_event.dart';
import '../models/models.dart';

/// Изменения журналов (подходы, операции, события) с момента последнего успешного сохранения.
///
/// Контроллер заполняет его при каждой мутации журнала, а репозиторий применяет точечно —
/// без обхода и сериализации всех записей. Если точный перечень изменений неизвестен
/// (импорт, сброс, ошибка записи), ставится [full]: журналы переписываются целиком.
class ChangeSet {
  bool full;
  final Map<String, WorkoutSet> setUpserts = {};
  final Set<String> setDeletes = {};
  final Map<String, MoneyTx> txUpserts = {};
  final Set<String> txDeletes = {};
  final Map<String, LifeEvent> eventUpserts = {};
  final Set<String> eventDeletes = {};

  ChangeSet({this.full = false});

  bool get isEmpty => !full && setUpserts.isEmpty && setDeletes.isEmpty && txUpserts.isEmpty && txDeletes.isEmpty && eventUpserts.isEmpty && eventDeletes.isEmpty;

  void upsertSet(WorkoutSet s) {
    setDeletes.remove(s.id);
    setUpserts[s.id] = s;
  }

  void deleteSet(String id) {
    setUpserts.remove(id);
    setDeletes.add(id);
  }

  void upsertTx(MoneyTx t) {
    txDeletes.remove(t.id);
    txUpserts[t.id] = t;
  }

  void deleteTx(String id) {
    txUpserts.remove(id);
    txDeletes.add(id);
  }

  void upsertEvent(LifeEvent e) {
    eventDeletes.remove(e.id);
    eventUpserts[e.id] = e;
  }

  void deleteEvent(String id) {
    eventUpserts.remove(id);
    eventDeletes.add(id);
  }

  /// Переписать журналы целиком; точечные записи при этом не нужны.
  void markFull() {
    full = true;
    setUpserts.clear();
    setDeletes.clear();
    txUpserts.clear();
    txDeletes.clear();
    eventUpserts.clear();
    eventDeletes.clear();
  }
}
