import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Диалог подтверждения. true — пользователь подтвердил.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Подтвердить',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: Text(message, style: const TextStyle(color: AppColors.text, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена', style: TextStyle(color: AppColors.muted))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: danger ? AppColors.red : AppColors.accent),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel, style: TextStyle(color: danger ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
  return r ?? false;
}
