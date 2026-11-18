import 'dart:typed_data';

/// Выбор файла пользователем. Плагин — только в реализации (`file_selector_source.dart`): интерфейс позволяет
/// тестировать экраны без устройства и заменить плагин, не трогая логику.

class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile(this.name, this.bytes);
}

/// Файл больше допустимого — не читается.
class FileTooLargeException implements Exception {
  const FileTooLargeException();
}

abstract class FileSource {
  /// Файл выписки, выбранный человеком; null — выбор отменён.
  Future<PickedFile?> pickStatement();
}

/// Для тестов: возвращает заранее заданный файл.
class FakeFileSource implements FileSource {
  PickedFile? next;
  Object? error;
  int calls = 0;
  FakeFileSource([this.next]);

  @override
  Future<PickedFile?> pickStatement() async {
    calls++;
    if (error != null) throw error!;
    return next;
  }
}
