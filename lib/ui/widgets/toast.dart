import 'package:flutter/material.dart';

/// Короткое сообщение внизу экрана. Новое сообщение сразу заменяет предыдущее, а не ждёт в очереди.
void showToast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
