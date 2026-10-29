import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/change_set.dart';
import 'package:life_os/models/models.dart';

WorkoutSet ws(String id) => WorkoutSet(id: id, muscleId: 'chest', at: DateTime(2026, 10, 24), weight: 10, reps: 5);
MoneyTx tx(String id) => MoneyTx(id: id, at: DateTime(2026, 10, 24), isIncome: false, amount: 1, categoryId: 'food');

void main() {
  test('новый ChangeSet пуст', () => expect(ChangeSet().isEmpty, isTrue));

  test('upsert после delete отменяет удаление, и наоборот', () {
    final c = ChangeSet()
      ..deleteSet('a')
      ..upsertSet(ws('a'));
    expect(c.setDeletes, isEmpty);
    expect(c.setUpserts.keys, ['a']);
    c.deleteSet('a');
    expect(c.setUpserts, isEmpty);
    expect(c.setDeletes, {'a'});
  });

  test('то же для операций; повторный upsert заменяет значение', () {
    final c = ChangeSet()
      ..upsertTx(tx('t'))
      ..deleteTx('t')
      ..upsertTx(tx('t'));
    expect(c.txDeletes, isEmpty);
    expect(c.txUpserts.length, 1);
    final newer = MoneyTx(id: 't', at: DateTime(2026, 10, 25), isIncome: true, amount: 9, categoryId: 'salary');
    c.upsertTx(newer);
    expect(c.txUpserts['t']!.amount, 9);
  });

  test('markFull очищает точечные записи и выставляет full', () {
    final c = ChangeSet()
      ..upsertSet(ws('a'))
      ..deleteTx('t')
      ..markFull();
    expect(c.full, isTrue);
    expect(c.setUpserts, isEmpty);
    expect(c.txDeletes, isEmpty);
    expect(c.isEmpty, isFalse);
  });

  test('isEmpty учитывает все части', () {
    expect((ChangeSet()..upsertSet(ws('a'))).isEmpty, isFalse);
    expect((ChangeSet()..deleteSet('a')).isEmpty, isFalse);
    expect((ChangeSet()..upsertTx(tx('a'))).isEmpty, isFalse);
    expect((ChangeSet()..deleteTx('a')).isEmpty, isFalse);
  });

  test('AppData.toJson(includeLogs: false) не содержит журналов, по умолчанию содержит', () {
    final d = AppData.defaults(now: DateTime(2026, 10, 24))
      ..workoutSets.add(ws('a'))
      ..transactions.add(tx('t'));
    final small = d.toJson(includeLogs: false);
    expect(small.containsKey('workoutSets'), isFalse);
    expect(small.containsKey('transactions'), isFalse);
    expect(small.containsKey('goals'), isTrue);
    final full = d.toJson();
    expect((full['workoutSets'] as List).length, 1);
    expect((full['transactions'] as List).length, 1);
  });
}
