import 'package:file_selector/file_selector.dart';

import 'file_source.dart';

/// Системный выбор файла (официальный плагин file_selector; Android — Storage Access Framework).
/// Файл читается в память и никуда не копируется и не отправляется. Тип не ограничивается: на части телефонов
/// фильтр по типу прячет нужные CSV — содержимое проверяется уже после выбора.
class FileSelectorSource implements FileSource {
  /// Больше не читаем вовсе: это не выписка, а держать такое в памяти незачем.
  final int maxBytes;
  const FileSelectorSource({this.maxBytes = 5 * 1024 * 1024});

  @override
  Future<PickedFile?> pickStatement() async {
    final f = await openFile();
    if (f == null) return null;
    // размер до чтения: огромный файл не загружается в память целиком
    if (await f.length() > maxBytes) throw const FileTooLargeException();
    return PickedFile(f.name, await f.readAsBytes());
  }
}
