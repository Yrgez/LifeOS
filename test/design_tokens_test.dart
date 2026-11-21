import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:catenna/core/theme.dart';

/// Оформление держится на токенах темы (CLAUDE.md, «Дизайн»): иначе разнобой возвращается с каждым новым экраном.
void main() {
  final files = [
    for (final f in Directory('lib/ui').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f,
    File('lib/core/theme.dart'),
  ];

  List<String> offenders(RegExp rx, {bool Function(Match m)? bad}) => [
        for (final f in files)
          for (final (i, line) in f.readAsLinesSync().indexed)
            for (final m in rx.allMatches(line))
              if (bad == null || bad(m)) '${f.path}:${i + 1}: ${m.group(0)}',
      ];

  test('размеры шрифта — только из шкалы AppText.scale', () {
    expect(offenders(RegExp(r'fontSize: (\d+(?:\.\d+)?)'), bad: (m) => !AppText.scale.contains(double.parse(m.group(1)!))), isEmpty);
  });

  test('радиусы — токены AppRadii, а не числа', () {
    expect(offenders(RegExp(r'(?:BorderRadius\.circular|tileDecoration\(radius:) ?\(?\d')), isEmpty);
  });

  test('цвет текста — из палитры, а не полупрозрачный белый', () {
    expect(offenders(RegExp(r'Colors\.white(?:60|70)\b')), isEmpty);
  });
}
