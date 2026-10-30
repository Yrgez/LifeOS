import 'package:flutter/material.dart';

/// Короткое сообщение внизу экрана.
void showToast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
