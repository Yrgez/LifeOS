import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/statement_import.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/sqlite_app_repository.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:life_os/ui/screens/statement_import_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Похоже на выгрузку банка: шапка над таблицей, «;», кавычки, копейки через запятую, неразрывные пробелы.
const tinkoffLike = 'Выписка по счёту 40817…\n'
    'Дата операции;Дата платежа;Статус;Сумма операции;Валюта;Категория;Описание\n'
    '17.11.2026 19:40:11;17.11.2026;OK;-450,00;RUB;Рестораны;"Кофейня ""Зерно"""\n'
    '17.11.2026 08:10:00;17.11.2026;OK;-450,00;RUB;Рестораны;"Кофейня ""Зерно"""\n'
    '15.11.2026 10:00:00;15.11.2026;OK;120 000,00;RUB;Зарплата;Аванс\n'
    'вчера;;OK;-100;RUB;;Ошибка даты\n'
    '14.11.2026 12:00:00;14.11.2026;OK;;RUB;;Без суммы\n';

void main() {
  setUpAll(sqfliteFfiInit);
  final now = DateTime(2026, 11, 18, 12);
  AppController make({AppRepository? repo, int maxTx = kMaxTransactions}) => AppController(repo ?? MemoryAppRepository(),
      clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n), maxTransactions: maxTx);

  group('разбор', () {
    test('суммы в разных записях', () {
      expect(parseStatementAmount('-1 234,56'), -1235);
      expect(parseStatementAmount('1,234.56'), 1235);
      expect(parseStatementAmount('1.234,40'), 1234);
      expect(parseStatementAmount('−500 ₽'), -500);
      expect(parseStatementAmount('(300.00)'), -300);
      expect(parseStatementAmount('1,5'), 2);
      expect(parseStatementAmount('12,345'), 12345); // запятая — разряды
      expect(parseStatementAmount('1.234.567'), 1234567);
      expect(parseStatementAmount('abc'), isNull);
    });

    test('даты: без времени — полдень; неверный календарь отвергается', () {
      expect(parseStatementDate('17.11.2026'), DateTime(2026, 11, 17, 12));
      expect(parseStatementDate('17.11.2026 19:40:11'), DateTime(2026, 11, 17, 19, 40, 11));
      expect(parseStatementDate('2026-11-17T08:05'), DateTime(2026, 11, 17, 8, 5));
      expect(parseStatementDate('17/11/26'), DateTime(2026, 11, 17, 12));
      expect(parseStatementDate('31.02.2026'), isNull);
      expect(parseStatementDate('вчера'), isNull);
    });

    test('CSV: разделитель, кавычки, перенос внутри кавычек', () {
      expect(detectDelimiter('a,b,c\n1,2,3'), ',');
      expect(detectDelimiter('a;b;c\n"1,5";2;3'), ';');
      final r = parseCsvRecords('a;b\n"много\nстрок";"он сказал ""да"""\nx;y', ';');
      expect(r.length, 3);
      expect(r[1].$2, ['много\nстрок', 'он сказал "да"']);
      expect(r[2].$1, 4); // номер строки файла учитывает перенос внутри кавычек
    });

    test('выписка: шапка над таблицей, колонки по названиям, причины отказа с номерами строк', () {
      final t = parseCsvTable(tinkoffLike);
      expect(t.header.first, 'Дата операции');
      final m = detectMapping(t.header);
      expect((m.date, m.amount, m.note), (0, 3, 6)); // «Описание», а не «Категория»
      final p = parseStatement(tinkoffLike, m, now: now);
      expect(p.rows.length, 3);
      expect(p.rows.first.note, 'Кофейня "Зерно"');
      expect(p.rows[2].signed, 120000);
      expect([for (final r in p.rejected) r.line], [6, 7]);
      expect(p.rejected.first.reason, contains('дата'));
      expect(p.rejected.last.reason, contains('сумма'));
    });

    test('отдельные колонки «приход» и «расход»', () {
      const csv = 'Дата,Описание,Приход,Расход\n2026-11-10,Перевод,"5,000.00",\n2026-11-11,Такси,,350';
      final m = detectMapping(parseCsvTable(csv).header);
      expect((m.amount, m.income, m.expense), (null, 2, 3));
      final p = parseStatement(csv, m, now: now);
      expect([for (final r in p.rows) r.signed], [5000, -350]);
    });

    test('повторы считаются по количеству', () {
      final a = StatementRow(1, DateTime(2026, 11, 17, 8), -450, 'Кофе');
      final b = StatementRow(2, DateTime(2026, 11, 17, 19), -450, 'Кофе');
      final s = splitDuplicates([a, b], [a.fingerprint]);
      expect((s.fresh.length, s.duplicates.length), (1, 1));
    });
  });

  group('контроллер', () {
    test('импорт, повторный импорт без повторов, капитал, отмена', () {
      final c = make();
      final m = detectMapping(parseCsvTable(tinkoffLike).header);
      final before = c.netWorth;
      final id = c.importStatement(tinkoffLike, m, name: 'Банк, ноябрь')!;
      expect(c.transactions.length, 3);
      expect(c.transactions.every((t) => t.importId == id), isTrue);
      // строки выписки идут не по порядку, а журнал сортируется один раз в конце импорта
      for (var i = 1; i < c.transactions.length; i++) {
        expect(c.transactions[i - 1].at.isAfter(c.transactions[i].at), isFalse);
      }
      expect(c.transactions.where((t) => !t.isIncome).every((t) => t.categoryId == 'other_exp'), isTrue);
      expect(c.netWorth, before); // по умолчанию капитал не меняется

      final again = c.previewStatement(tinkoffLike, m);
      expect((again.fresh.length, again.duplicates.length), (0, 3));
      expect(c.importStatement(tinkoffLike, m, name: 'ещё раз'), isNull); // нечего добавить

      final withNw = c.importStatement('Дата;Сумма;Описание\n16.11.2026;-1000;Ужин', const ColumnMapping(date: 0, amount: 1, note: 2),
          name: 'Ужин', affectsNetWorth: true)!;
      expect(c.netWorth, before - 1000);
      expect(c.undoImport(withNw), 1);
      expect(c.netWorth, before);
      expect(c.undoImport(withNw), isNull);
      expect(c.statementImports.length, 2); // запись импорта остаётся
      expect(c.statementImports.last.undoneAt, isNotNull);
      expect(c.exportCsv('transactions')!.split('\n').first, endsWith('импорт'));
    });

    test('неверные категории и переполнение журнала отвергаются', () {
      final c = make(maxTx: 2);
      final m = detectMapping(parseCsvTable(tinkoffLike).header);
      expect(c.importStatement(tinkoffLike, m, name: 'x', expenseCategory: 'salary'), isNull);
      expect(c.importStatement(tinkoffLike, m, name: ' '), isNull);
      expect(c.importStatement(tinkoffLike, m, name: 'x'), isNull); // 3 операции в журнал на 2
      expect(c.transactions, isEmpty);
    });

    test('SQLite: источник операции хранится; база версии 3 получает колонку при обновлении', () async {
      final dir = await Directory.systemTemp.createTemp('lifeos_import');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/v3.db';
      // база старой версии: таблица операций без import_id
      final old = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
            version: 3,
            onCreate: (db, v) async {
              await SqliteAppRepository.onCreateSchema(db, v);
              await db.execute('ALTER TABLE money_tx DROP COLUMN import_id');
            },
          ));
      await old.close();
      final db = await SqliteAppRepository.openDb(databaseFactoryFfi, path);
      addTearDown(db.close);
      expect(await db.getVersion(), kDbVersion);
      final c = make(repo: SqliteAppRepository(opener: () async => db));
      await c.load();
      final id = c.importStatement(tinkoffLike, detectMapping(parseCsvTable(tinkoffLike).header), name: 'Банк')!;
      await c.flush();
      final c2 = make(repo: SqliteAppRepository(opener: () async => db));
      await c2.load();
      expect(c2.transactions.where((t) => t.importId == id).length, 3);
      expect(c2.statementImports.single.name, 'Банк');
    });
  });

  testWidgets('экран: вставка, предпросмотр, импорт, отмена (360 px)', (tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(MemoryAppRepository(), clock: () => now, saveDelay: Duration.zero, initialData: (n) => AppData.blank(now: n));
    await c.load();
    await tester.pumpWidget(MaterialApp(home: StatementImportScreen(controller: c)));
    await tester.enterText(find.byKey(const ValueKey('import_text')), tinkoffLike);
    await tester.pumpAndSettle();
    expect(find.text('Новых операций: 3'), findsOneWidget);
    expect(find.text('Не распознано строк: 2'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('import_name')), 'Банк, ноябрь');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('import_run')));
    await tester.tap(find.byKey(const ValueKey('import_run')));
    await tester.pumpAndSettle();
    expect(c.transactions.length, 3);
    final imp = c.statementImports.single;
    await tester.ensureVisible(find.byKey(ValueKey('import_undo_${imp.id}')));
    await tester.tap(find.byKey(ValueKey('import_undo_${imp.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отменить импорт').last);
    await tester.pumpAndSettle();
    expect(c.transactions, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5)); // всплывающие подсказки
    c.dispose();
  });
}
