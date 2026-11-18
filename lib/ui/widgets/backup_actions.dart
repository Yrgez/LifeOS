import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../security/backup_cipher.dart';
import '../../state/app_controller.dart';
import '../../core/text_decoding.dart';
import '../../data/file_selector_source.dart';
import '../../data/file_source.dart';
import 'confirm_dialog.dart';
import 'form_dialog.dart';
import 'progress_dialog.dart';
import 'toast.dart';

/// Предел файла копии: десятилетия журналов — единицы мегабайт; больше — точно не наша копия.
const maxBackupFileBytes = 100 * 1024 * 1024;

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
  await importBackupText(context, c, r['json']!, cipher: cipher);
}

/// Восстановление из файла копии (в том числе автокопии из папки). Файл выбирает человек.
Future<void> restoreFromFile(
  BuildContext context,
  AppController c, {
  FileSource files = const FileSelectorSource(maxBytes: maxBackupFileBytes),
  BackupCipher cipher = const BackupCipher(useIsolate: true),
}) async {
  PickedFile? f;
  try {
    f = await files.pickFile();
  } on FileTooLargeException {
    if (context.mounted) showToast(context, 'Файл слишком большой для резервной копии');
    return;
  } catch (_) {
    if (context.mounted) showToast(context, 'Не удалось открыть файл');
    return;
  }
  if (f == null || !context.mounted) return;
  final d = decodeStatementBytes(f.bytes);
  if (d == null) {
    showToast(context, 'Это не файл резервной копии LIFE OS');
    return;
  }
  final ok = await confirmDialog(context,
      title: 'Восстановить из «${f.name}»?', message: 'Текущие данные будут заменены данными из копии.', confirmLabel: 'Продолжить', danger: true);
  if (!ok || !context.mounted) return;
  await importBackupText(context, c, d.text, cipher: cipher);
}

/// Копия (обычная или зашифрованная) → замена данных. Для зашифрованной спрашивается пароль.
Future<void> importBackupText(BuildContext context, AppController c, String raw, {BackupCipher cipher = const BackupCipher(useIsolate: true)}) async {
  var text = raw.trim();
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
