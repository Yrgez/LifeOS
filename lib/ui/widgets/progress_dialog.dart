import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Показывает неотменяемое окно с индикатором на время длинной операции (шифрование, расшифровка).
Future<T> runWithProgress<T>(BuildContext context, String message, Future<T> Function() action) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppColors.card,
        content: Row(
          children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.green)),
            const SizedBox(width: 16),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 14))),
          ],
        ),
      ),
    ),
  ));
  try {
    return await action();
  } finally {
    navigator.pop();
  }
}
