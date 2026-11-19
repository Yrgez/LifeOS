import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/finance_categories.dart';
import 'package:life_os/core/import_rules.dart';
import 'package:life_os/core/statement_import.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/sqlite_app_repository.dart';
import 'package:life_os/models/finance_rules.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:life_os/ui/screens/categories_screen.dart';
import 'package:life_os/ui/screens/statement_import_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'statement_import_test.dart' show tinkoffLike;

void main() {
  setUpAll(sqfliteFfiInit);
  final now = DateTime(2026, 11, 18, 12);
  AppController make([AppRepository? repo]) =>
      AppController(repo ?? MemoryAppRepository(), clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n));
  ColumnMapping mapping() => detectMapping(parseCsvTable(tinkoffLike).header);

  group('правила', () {
    test('совпадение без учёта регистра и «ё», по знаку операции, первое подходящее', () {
      final rules = [
        ImportRule(id: '1', pattern: 'Пятёрочка', categoryId: 'food', createdAt: now),
        ImportRule(id: '2', pattern: 'пятерочка доставка', categoryId: 'shopping', createdAt: now),
        ImportRule(id: '3', pattern: 'Аванс', categoryId: 'salary', createdAt: now),
      ];
      expect(categoryByRules('ПЯТЕРОЧКА доставка 1234', false, rules), 'food');
      expect(categoryByRules('Аванс за ноябрь', true, rules), 'salary');
      expect(categoryByRules('Аванс за ноябрь', false, rules), isNull); // правило дохода к расходу не применяется
      expect(categoryByRules('', false, rules), isNull);
    });

    test('образец из описания и частые описания без правила', () {
      expect(suggestPattern('Пятёрочка 1234 Москва'), 'Пятёрочка');
      expect(suggestPattern('YANDEX*GO 4421'), 'YANDEX');
      expect(suggestPattern('Кофейня "Зерно"'), 'Кофейня "Зерно"');
      expect(suggestPattern('1234'), isNull);
      final rows = [('Пятёрочка 1', false), ('пятёрочка 2', false), ('Магнит 3', false), ('Такси', false)];
      expect(unmatchedPatterns(rows, [ImportRule(id: 'r', pattern: 'такси', categoryId: 'transport', createdAt: now)]),
          [('Пятёрочка', 2), ('Магнит', 1)]);
    });

    test('модели: JSON и проверка', () {
      final c = CustomCategory(id: 'u_1', name: 'Дети', isIncome: false, icon: 'child');
      expect(jsonEncode(CustomCategory.tryFromJson(c.toJson())!.toJson()), jsonEncode(c.toJson()));
      expect(CustomCategory.tryFromJson({...c.toJson(), 'id': 'food'}), isNull); // своя категория не прячется под встроенный id
      final r = ImportRule(id: 'r', pattern: 'Магнит', categoryId: 'food', createdAt: now);
      expect(jsonEncode(ImportRule.tryFromJson(r.toJson())!.toJson()), jsonEncode(r.toJson()));
      expect(ImportRule.tryFromJson({...r.toJson(), 'p': 'М'}), isNull);
    });
  });

  group('контроллер', () {
    test('свои категории: в поиске и выборе, архив прячет из выбора, но не из истории', () {
      final c = make();
      final id = c.addCategory('Дети', isIncome: false, icon: 'child')!;
      expect(c.addCategory('дети', isIncome: false), isNull); // такое название уже есть
      expect(c.addCategory('Еда', isIncome: false), isNull); // совпадает со встроенной
      expect(finCategory(id)!.name, 'Дети');
      c.addTransaction(categoryId: id, amount: 3000);
      expect(c.transactions.single.isIncome, isFalse);
      c.archiveCategory(id);
      expect(pickableFinCategories(income: false).any((x) => x.id == id), isFalse);
      expect(pickableFinCategories(income: false, keep: id).any((x) => x.id == id), isTrue);
      expect(finCategory(id), isNotNull); // старые операции по-прежнему с названием
      expect(c.updateCategory(id, name: 'Дети и школа', icon: 'school'), isTrue);
      expect(finCategory(c.transactions.single.categoryId)!.name, 'Дети и школа');
    });

    test('импорт применяет правила; остальное — в категорию по умолчанию', () {
      final c = make();
      c.addImportRule('кофейня', 'food');
      c.addImportRule('Аванс', 'salary');
      final p = c.previewStatement(tinkoffLike, mapping());
      expect(c.statementRuleHits(p.fresh), 3);
      c.importStatement(tinkoffLike, mapping(), name: 'Банк');
      expect({for (final t in c.transactions) t.categoryId}, {'food', 'salary'});
    });

    test('правила задним числом трогают только «Прочее» из выписки', () {
      final c = make();
      c.importStatement(tinkoffLike, mapping(), name: 'Банк');
      expect(c.transactions.where((t) => t.categoryId == 'other_exp').length, 2);
      // одну операцию человек разнёс сам — её правило не перезапишет
      final mine = c.transactions.firstWhere((t) => !t.isIncome);
      c.updateTransaction(mine.id, categoryId: 'fun', amount: mine.amount, at: mine.at, note: mine.note, affectsNetWorth: mine.affectsNetWorth);
      c.addImportRule('кофейня', 'food');
      expect(c.rulesWouldRecategorize().length, 1);
      expect(c.applyRulesToImported(), 1);
      expect(c.transactions.where((t) => !t.isIncome).map((t) => t.categoryId).toSet(), {'fun', 'food'});
      expect(c.transactions.every((t) => t.importId != null), isTrue); // источник сохраняется
      expect(c.applyRulesToImported(), 0);
    });

    test('тот же образец заменяет категорию; удаление правила', () {
      final c = make();
      c.addImportRule('Магнит', 'food');
      c.addImportRule('магнит', 'shopping');
      expect(c.importRules.single.categoryId, 'shopping');
      expect(c.removeImportRule(c.importRules.single.id), isTrue);
      expect(c.addImportRule('М', 'food'), isNull);
      expect(c.addImportRule('Магнит', 'нет такой'), isNull);
    });

    test('хранится в SQLite и в копии; битое правило в строгом импорте отвергается', () async {
      final db = await SqliteAppRepository.openDb(databaseFactoryFfi, inMemoryDatabasePath);
      addTearDown(db.close);
      final c = make(SqliteAppRepository(opener: () async => db));
      await c.load();
      final id = c.addCategory('Животные', isIncome: false, icon: 'pets')!;
      c.addImportRule('Зоомагазин', id);
      await c.flush();
      final c2 = make(SqliteAppRepository(opener: () async => db));
      await c2.load();
      expect(c2.customCategories.single.name, 'Животные');
      expect(c2.importRules.single.categoryId, id);
      expect(finCategory(id)!.name, 'Животные');
      final j = jsonDecode(c.exportBackup()) as Map<String, dynamic>;
      expect(j['schemaVersion'], greaterThanOrEqualTo(21));
      expect(() => AppData.fromJson({...j, 'importRules': [{'id': 'x', 'p': 'а', 'c': 'food', 't': 1}]}, strict: true), throwsFormatException);
    });
  });

  testWidgets('экраны: своя категория, правило из предпросмотра импорта (360 px)', (tester) async {
    tester.view.physicalSize = const Size(360, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(MemoryAppRepository(), clock: () => now, saveDelay: Duration.zero, initialData: (n) => AppData.blank(now: n));
    await c.load();
    await tester.pumpWidget(MaterialApp(home: CategoriesScreen(controller: c)));
    await tester.tap(find.byKey(const ValueKey('add_category')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Дети');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(c.customCategories.single.name, 'Дети');

    await tester.pumpWidget(MaterialApp(home: StatementImportScreen(controller: c)));
    await tester.enterText(find.byKey(const ValueKey('import_text')), tinkoffLike);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('rule_for_Кофейня "Зерно"')));
    await tester.tap(find.byKey(const ValueKey('rule_for_Кофейня "Зерно"')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Запомнить'));
    await tester.pumpAndSettle();
    expect(c.importRules.single.pattern, 'Кофейня "Зерно"');
    expect(find.textContaining('По вашим правилам разберётся 2 из 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    c.dispose();
  });
}
