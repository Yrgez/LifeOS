import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catenna/core/theme.dart';

void main() {
  test('волна нажатия — без шейдера (конфигурация, проверенная на Galaxy S10)', () {
    expect(buildAppTheme().splashFactory, InkRipple.splashFactory);
  });
}
