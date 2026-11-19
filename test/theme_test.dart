import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/theme.dart';

void main() {
  test('волна нажатия — без шейдера (InkSparkle на части GPU оставляет полосы шума и битые буквы)', () {
    expect(buildAppTheme().splashFactory, InkRipple.splashFactory);
  });
}
