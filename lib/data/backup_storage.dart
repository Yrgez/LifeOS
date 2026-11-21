import 'dart:typed_data';

/// Место для резервных копий вне базы приложения: папка, выбранная человеком (на Android — через системный
/// проводник, в том числе облачная). Плагин — только в реализации (`folder_backup_storage.dart`).

class StoredBackup {
  final String id;
  final String name;
  const StoredBackup(this.id, this.name);
}

abstract class BackupStorage {
  /// Выбор папки; адрес папки или null, если выбор отменён. Бросает, если выбор невозможен.
  Future<String?> pickFolder();

  /// Доступ к папке ещё есть (его можно отозвать или удалить папку).
  Future<bool> hasAccess(String folder);

  /// Отображаемое имя папки.
  Future<String?> folderName(String folder);

  Future<void> write(String folder, String name, Uint8List bytes);
  Future<List<StoredBackup>> list(String folder);
  Future<void> delete(String folder, String id);

  /// «Сохранить как» в месте, которое человек выберет сам (открытый экспорт). false — отменено.
  Future<bool> saveAs(String name, Uint8List bytes, String mime);
}

/// Хранилище недоступно на этой платформе (тесты, компьютер): автокопия просто не предлагается.
class UnsupportedBackupStorage implements BackupStorage {
  const UnsupportedBackupStorage();
  @override
  Future<String?> pickFolder() => throw UnsupportedError('Папка для копий недоступна на этой платформе');
  @override
  Future<bool> hasAccess(String folder) async => false;
  @override
  Future<String?> folderName(String folder) async => null;
  @override
  Future<void> write(String folder, String name, Uint8List bytes) => throw UnsupportedError('нет хранилища');
  @override
  Future<bool> saveAs(String name, Uint8List bytes, String mime) => throw UnsupportedError('нет хранилища');
  @override
  Future<List<StoredBackup>> list(String folder) async => const [];
  @override
  Future<void> delete(String folder, String id) async {}
}

/// Для тестов: папки и файлы в памяти.
class MemoryBackupStorage implements BackupStorage {
  final Map<String, Map<String, Uint8List>> folders = {};
  String? nextPick = 'content://папка/копии';
  bool access = true;
  Object? writeError;

  /// Файлы, сохранённые через «Сохранить как»; [saveAsCancelled] — человек закрыл диалог.
  final Map<String, Uint8List> savedAs = {};
  bool saveAsCancelled = false;

  @override
  Future<bool> saveAs(String name, Uint8List bytes, String mime) async {
    if (saveAsCancelled) return false;
    savedAs[name] = bytes;
    return true;
  }

  @override
  Future<String?> pickFolder() async {
    final f = nextPick;
    if (f != null) folders.putIfAbsent(f, () => {});
    return f;
  }

  @override
  Future<bool> hasAccess(String folder) async => access && folders.containsKey(folder);

  @override
  Future<String?> folderName(String folder) async => folder.split('/').last;

  @override
  Future<void> write(String folder, String name, Uint8List bytes) async {
    if (writeError != null) throw writeError!;
    (folders[folder] ??= {})[name] = bytes;
  }

  @override
  Future<List<StoredBackup>> list(String folder) async => [for (final n in folders[folder]?.keys ?? const <String>[]) StoredBackup(n, n)];

  @override
  Future<void> delete(String folder, String id) async => folders[folder]?.remove(id);
}
