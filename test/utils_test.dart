import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/utils.dart';

void main() {
  group('oneRM', () {
    test('1 повтор — это сам вес', () => expect(oneRM(100, 1), 100));
    test('Бжицки до 10 повторов: 100 × 5 ≈ 112.5', () => expect(oneRM(100, 5), closeTo(112.5, 0.01)));
    test('Эпли после 10 повторов: 100 × 15 = 150', () => expect(oneRM(100, 15), closeTo(150, 0.01)));
    test('формула не «взрывается» на 36+ повторах', () => expect(oneRM(50, 40).isFinite, isTrue));
  });

  group('парсинг и формат', () {
    test('запятая как десятичный разделитель', () => expect(parseNum('82,5'), 82.5));
    test('пробелы в числе', () => expect(parseInt('1 000'), 1000));
    test('мусор → null', () => expect(parseNum('abc'), isNull));
    test('fmtMoney', () => expect(fmtMoney(1000000), '1\u00A0000\u00A0000'));
    test('fmtMoney отрицательные', () => expect(fmtMoney(-1500), '-1\u00A0500'));
    test('trimNum', () {
      expect(trimNum(80), '80');
      expect(trimNum(82.5), '82.5');
    });
    test('dayKey', () => expect(dayKey(DateTime(2026, 3, 7)), '2026-03-07'));
    test('clampD', () {
      expect(clampD(5, 0, 1), 1);
      expect(clampD(-5, 0, 1), 0);
    });
  });

  group('форматирование объёма и дат', () {
    test('fmtVolume', () {
      expect(fmtVolume(850), '850');
      expect(fmtVolume(4200), '4\u00A0200');
      expect(fmtVolume(12400), '12.4 т');
    });
    test('shortDate', () => expect(shortDate(DateTime(2026, 10, 24)), 'Сб, 24 окт'));
  });

  group('даты', () {
    test('parseDate: разные разделители', () {
      expect(parseDate('24.10.2026'), DateTime(2026, 10, 24));
      expect(parseDate(' 1/2/2027 '), DateTime(2027, 2, 1));
      expect(parseDate('05-03-2026'), DateTime(2026, 3, 5));
    });
    test('parseDate: несуществующие и мусор → null', () {
      expect(parseDate('31.02.2026'), isNull);
      expect(parseDate('32.01.2026'), isNull);
      expect(parseDate('abc'), isNull);
      expect(parseDate('24.10.26'), isNull);
      expect(parseDate(''), isNull);
    });
    test('fmtDate', () => expect(fmtDate(DateTime(2026, 3, 5)), '05.03.2026'));
  });

  test('fmtCompact: меньше тысячи — как есть, а не «0к»; дальше — к и М с запятой', () {
    expect(fmtCompact(0), '0');
    expect(fmtCompact(850), '850');
    expect(fmtCompact(999), '999');
    expect(fmtCompact(1000), '1к');
    expect(fmtCompact(1500), '1,5к');
    expect(fmtCompact(8420), '8,4к');
    expect(fmtCompact(12400), '12к');
    expect(fmtCompact(380000), '380к');
    expect(fmtCompact(999600), '1М'); // не «1000к»
    expect(fmtCompact(1250000), '1,25М');
    expect(fmtCompact(2450000), '2,45М');
    expect(fmtCompact(15300000), '15,3М');
    expect(fmtCompact(-1500), '−1,5к');
  });
}
