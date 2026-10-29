import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../security/backup_cipher.dart';
import '../../state/app_controller.dart';
import 'form_dialog.dart';
import 'progress_dialog.dart';
import 'toast.dart';

/// Резервная копия: экспорт в буфер обмена (по желанию — с шифрованием паролем) и импорт.
/// Зашифрованная копия — JSON-контейнер AES-256-GCM; без пароля её не прочитать, а пароль не восстановить.
Future<void> exportBackup(BuildContext context, AppController c, {BackupCipher cipher = const BackupCipher(useIsolate: true)}) async {
  final r = await showFormDialog(
    context,
    title: 'Экспорт резервной копии',
    actionLabel: 'Экспортировать',
    fields: const [
      FieldSpec('mode', 'Формат', initial: 'enc', options: {
        'enc': 'Зашифровать паролем (рекомендуется)',
        'plain': 'Без шифрования — читается любым приложением',
      }),
      FieldSpec('p', 'Пароль (от 8 символов, нужен только для шифрования)', obscure: true),
      FieldSpec('p2', 'Повторите пароль', obscure: true),
    ],
    validate: (v) => v['mode'] == 'plain' || (v['p']!.length >= BackupCipher.minPassphraseLength && v['p'] == v['p2']),
  );
  if (r == null || !context.mounted) return;

  var text = c.exportBackup();
  final encrypted = r['mode'] == 'enc';
  if (encrypted) {
    try {
      text = await runWithProgress(context, 'Шифрование копии…', () => cipher.encrypt(text, r['p']!));
    } catch (_) {
      if (context.mounted) showToast(context, 'Не удалось зашифровать копию');
      return;
    }
    if (!context.mounted) return;
  }
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  showToast(context, encrypted ? 'Зашифрованная копия скопирована. Не забудьте пароль — восстановить его нельзя' : 'Копия скопирована в буфер обмена (без шифрования)');
}

Future<void> importBackupDialog(BuildContext context, AppController c, {BackupCipher cipher = const BackupCipher(useIsolate: true)}) async {
  final r = await showFormDialog(
    context,
    title: 'Импорт резервной копии',
    actionLabel: 'Далее',
    accent: AppColors.red,
    actionTextColor: Colors.white,
    fields: const [FieldSpec('json', 'Вставьте копию (обычную или зашифрованную)', lines: 6)],
    validate: (v) => v['json']!.isNotEmpty,
  );
  if (r == null || !context.mounted) return;

  var text = r['json']!.trim();
  if (BackupCipher.looksEncrypted(text)) {
    final pr = await showFormDialog(
      context,
      title: 'Копия зашифрована',
      actionLabel: 'Расшифровать и заменить данные',
      accent: AppColors.red,
      actionTextColor: Colors.white,
      fields: const [FieldSpec('p', 'Пароль', obscure: true)],
      validate: (v) => v['p']!.isNotEmpty,
    );
    if (pr == null || !context.mounted) return;
    try {
      text = await runWithProgress(context, 'Расшифровка…', () => cipher.decrypt(text, pr['p']!));
    } on BackupDecryptException catch (e) {
      if (context.mounted) showToast(context, e.message);
      return;
    }
    if (!context.mounted) return;
  }

  final ok = c.importBackup(text);
  showToast(context, ok ? 'Данные восстановлены' : 'Не удалось прочитать копию — данные не изменены');
}
