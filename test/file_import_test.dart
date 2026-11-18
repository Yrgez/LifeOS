import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/text_decoding.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/file_source.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:life_os/ui/screens/statement_import_screen.dart';

import 'statement_import_test.dart' show tinkoffLike;

/// Кодирование в Windows-1251 — обратное к декодеру (для подготовки «банковских» файлов в тестах).
Uint8List cp1251(String s) {
  final back = <int, int>{for (var b = 0; b < 256; b++) decodeWindows1251([b]).codeUnitAt(0): b};
  return Uint8List.fromList([for (final ch in s.codeUnits) back[ch] ?? (throw ArgumentError('нет в 1251: ${String.fromCharCode(ch)}'))]);
}

void main() {
  group('кодировка', () {
    test('UTF-8 с BOM и без, UTF-16, Windows-1251; двоичный файл — не текст', () {
      const s = 'Дата;Сумма;Описание\n17.11.2026;-450;Кофе «Зерно» Ёж';
      expect(decodeStatementBytes(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(s)]))!.text, s);
      final plain = decodeStatementBytes(Uint8List.fromList(utf8.encode(s)))!;
      expect((plain.text, plain.encoding), (s, 'UTF-8'));
      final win = decodeStatementBytes(cp1251(s))!;
      expect((win.text, win.encoding), (s, 'Windows-1251'));
      final le = <int>[0xFF, 0xFE];
      for (final u in s.codeUnits) {
        le..add(u & 0xFF)..add(u >> 8);
      }
      expect(decodeStatementBytes(Uint8List.fromList(le))!.text, s);
      // .xlsx — это zip: «PK\x03\x04» и нулевые байты
      expect(decodeStatementBytes(Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x06, 0x00])), isNull);
    });

    test('Windows-1251: русский алфавит целиком, Ё, неразрывный пробел, многоточие', () {
      final all = String.fromCharCodes([for (var c = 0x0410; c <= 0x044F; c++) c]);
      expect(decodeWindows1251(cp1251(all)), all);
      expect(decodeWindows1251([0xA8, 0xB8, 0xA0, 0x85]), 'Ёё …');
    });
  });

  group('экран', () {
    final now = DateTime(2026, 11, 18, 12);
    late AppController c;
    late FakeFileSource files;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      c = AppController(MemoryAppRepository(), clock: () => now, saveDelay: Duration.zero, initialData: (n) => AppData.blank(now: n));
      await c.load();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatementImportScreen(controller: c, files: files))));
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      c.dispose();
    }

    testWidgets('файл банка в Windows-1251: предпросмотр, название из имени файла, импорт', (tester) async {
      files = FakeFileSource(PickedFile('tinkoff_ноябрь.csv', cp1251(tinkoffLike)));
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('import_file')));
      await tester.pumpAndSettle();
      expect(files.calls, 1);
      expect(find.text('Новых операций: 3'), findsOneWidget);
      expect(find.text('Источник: tinkoff_ноябрь.csv · Windows-1251'), findsOneWidget);
      expect(find.textContaining('Кофейня "Зерно"'), findsWidgets); // русский текст не испорчен
      await tester.ensureVisible(find.byKey(const ValueKey('import_run')));
      await tester.tap(find.byKey(const ValueKey('import_run')));
      await tester.pumpAndSettle();
      expect(c.statementImports.single.name, 'tinkoff_ноябрь');
      expect(c.transactions.length, 3);
      expect(tester.takeException(), isNull);
      await close(tester);
    });

    testWidgets('не текст, слишком большой файл, ошибка выбора, отмена — понятное сообщение, ничего не ломается', (tester) async {
      files = FakeFileSource(PickedFile('выписка.xlsx', Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00])));
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('import_file')));
      await tester.pumpAndSettle();
      expect(find.textContaining('не текстовый CSV'), findsOneWidget);

      files.next = PickedFile('big.csv', Uint8List(StatementImportScreen.maxFileBytes + 1));
      await tester.tap(find.byKey(const ValueKey('import_file')));
      await tester.pumpAndSettle();
      expect(find.textContaining('больше 5 МБ'), findsOneWidget);

      // реализация на плагине проверяет размер до чтения и сообщает об этом исключением
      files.error = const FileTooLargeException();
      await tester.tap(find.byKey(const ValueKey('import_file')));
      await tester.pumpAndSettle();
      expect(find.textContaining('больше 5 МБ'), findsOneWidget);

      files.error = StateError('нет доступа');
      await tester.tap(find.byKey(const ValueKey('import_file')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Не удалось открыть файл'), findsOneWidget);

      files
        ..error = null
        ..next = null; // отмена выбора
      await tester.tap(find.byKey(const ValueKey('import_file')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('import_preview')), findsNothing);
      expect(c.transactions, isEmpty);
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  });
}
