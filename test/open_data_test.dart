import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/open_export.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/health_source.dart';
import 'package:life_os/models/life_event.dart';
import 'package:life_os/state/app_controller.dart';

void main() {
  late DateTime now;
  late FakeHealthSource src;

  AppController make() =>
      AppController(MemoryAppRepository(), clock: () => now, saveDelay: Duration.zero, health: src);

  setUp(() {
    now = DateTime(2026, 10, 24, 12);
    src = FakeHealthSource(data: {
      DateTime(2026, 10, 22): HealthDay(DateTime(2026, 10, 22), sleepMinutes: 400, weightKg: 81.2),
      DateTime(2026, 10, 23): HealthDay(DateTime(2026, 10, 23), steps: 5000, sleepMinutes: 450),
      DateTime(2026, 10, 24): HealthDay(DateTime(2026, 10, 24), steps: 3000, sleepMinutes: 420, weightKg: 80.6),
    });
  });

  group('сон и вес из Health Connect', () {
    test('сон попадает в дневные снимки — и за прошлые дни, и за сегодня', () async {
      final c = make();
      await c.load();
      await c.connectHealth();
      final s = c.snapshotsByDay;
      expect(s['2026-10-22']!.sleepMinutes, 400);
      expect(s['2026-10-23']!.sleepMinutes, 450);
      expect(s['2026-10-24']!.sleepMinutes, 420);
    });

    test('вес — одна запись в день с источником, обновляется на месте; ручные замеры не трогаются', () async {
      final c = make();
      await c.load();
      c.addWeight(82, at: DateTime(2026, 10, 22, 8));
      await c.connectHealth();
      final hc = [for (final w in c.weights) if (w.source == 'health') w];
      expect(hc.map((w) => w.kg), [81.2, 80.6]);
      expect(c.weights.where((w) => w.source == 'manual').single.kg, 82);

      src.data[DateTime(2026, 10, 24)] = HealthDay(DateTime(2026, 10, 24), weightKg: 80.4);
      await c.syncHealth();
      final again = [for (final w in c.weights) if (w.source == 'health') w];
      expect(again.length, 2);
      expect(again.last.kg, 80.4);
    });
  });

  group('открытый экспорт', () {
    test('поле CSV экранируется', () {
      expect(csvField('просто'), 'просто');
      expect(csvField('a,b'), '"a,b"');
      expect(csvField('сказал "да"'), '"сказал ""да"""');
      // CSV-инъекция: текст, похожий на формулу, не выполнится в таблице; числа не трогаются
      expect(csvField('=HYPERLINK("http://x")'), '"\'=HYPERLINK(""http://x"")"');
      expect(csvField('+7 900'), "'+7 900");
      expect(csvField('@сумма'), "'@сумма");
      expect(csvField(-500), '-500');
    });

    test('файл экспорта: CSV с меткой UTF-8 для Excel, Markdown без неё; тип для диалога сохранения', () {
      final csv = exportFileBytes('lifeos-events-2026-11-18.csv', 'когда,название');
      expect(csv.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(csv), 'когда,название'); // utf8.decode метку скрывает
      expect(exportFileBytes('lifeos-chronicle-2026-11-18.md', '# Хроника').first, '#'.codeUnitAt(0));
      expect(exportMime('a.csv'), 'text/csv');
      expect(exportMime('a.md'), 'text/markdown');
      expect(csvField('две\nстроки'), '"две\nстроки"');
      expect(csvField(null), '');
    });

    test('события: отменённые и версии остаются, с пометками', () async {
      final c = make();
      await c.load();
      final id = c.addEvent(title: 'Пробежка, 5 км', dimensions: [LifeDimension.body], note: 'легко')!;
      now = now.add(const Duration(minutes: 1));
      c.voidEvent(id);
      final csv = c.exportCsv('events')!;
      final lines = csv.trim().split('\n');
      expect(lines.first, startsWith('id,когда,записано'));
      expect(lines.length, 2);
      expect(lines[1], contains('"Пробежка, 5 км"'));
      expect(lines[1], contains('2026-10-24 12:01')); // время отмены
      expect(c.exportCsv('нет такого'), isNull);
    });

    test('операции, дни, вес, подходы — заголовок и строки', () async {
      final c = make();
      await c.load();
      await c.connectHealth();
      c.addTransaction(categoryId: 'shopping', amount: 1500, note: 'книги');
      expect(c.exportCsv('transactions')!.trim().split('\n').length, 2);
      final days = c.exportCsv('days')!;
      expect(days, contains('2026-10-23,5000'));
      expect(c.exportCsv('weights')!, contains('Health Connect'));
      expect(c.exportCsv('sets')!.split('\n').first, contains('1RM'));
    });

    test('хроника в Markdown: месяц, день, событие и заметка цитатой', () async {
      final c = make();
      await c.load();
      c.addEvent(title: 'Начал курс', dimensions: [LifeDimension.mind], note: 'первый урок\nвторая строка');
      final md = c.exportChronicleMarkdown();
      expect(md, startsWith('# Хроника'));
      expect(md, contains('## Октябрь 2026'));
      expect(md, contains('### 24.10.2026'));
      expect(md, contains('- 12:00 — Начал курс'));
      expect(md, contains('  > первый урок\n  > вторая строка'));
    });
  });
}
