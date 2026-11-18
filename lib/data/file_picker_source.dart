import 'package:file_picker/file_picker.dart';

import 'file_source.dart';

/// Системный выбор файла (Android: стандартный проводник). Файл читается целиком в память и никуда не
/// копируется и не отправляется. Тип не ограничивается расширением: на части телефонов фильтр «.csv»
/// прячет нужные файлы — содержимое проверяется уже после выбора.
class FilePickerSource implements FileSource {
  const FilePickerSource();

  @override
  Future<PickedFile?> pickStatement() async {
    final r = await FilePicker.pickFiles(withData: true);
    final f = r == null || r.files.isEmpty ? null : r.files.first;
    final bytes = f?.bytes;
    if (f == null || bytes == null) return null;
    return PickedFile(f.name, bytes);
  }
}
