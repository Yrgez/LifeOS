import 'package:flutter/services.dart';

/// Файл в папке копий.
class BackupFolderEntry {
  final String id; // идентификатор документа в папке
  final String name;
  final DateTime modified;
  final int size;
  const BackupFolderEntry(this.id, this.name, this.modified, this.size);
}

/// Папка для резервных копий на Android через Storage Access Framework. Человек выбирает папку один раз
/// (в том числе облачную, например Google Drive), приложение получает постоянный доступ только к ней.
class BackupFolder {
  static const _ch = MethodChannel('catenna/backup_folder');

  /// Выбор папки. Возвращает её адрес (content://…) или null, если выбор отменён.
  static Future<String?> pickFolder() => _ch.invokeMethod<String>('pickFolder');

  /// Доступ к папке ещё действует (его можно отозвать или удалить папку).
  static Future<bool> hasAccess(String folder) async => await _ch.invokeMethod<bool>('hasAccess', {'folder': folder}) ?? false;

  /// Отображаемое имя папки; null — недоступна.
  static Future<String?> folderName(String folder) => _ch.invokeMethod<String>('folderName', {'folder': folder});

  /// Создаёт файл в папке и записывает данные. Возвращает id созданного документа.
  static Future<String> writeFile(String folder, String name, Uint8List bytes, {String mime = 'application/octet-stream'}) async =>
      (await _ch.invokeMethod<String>('writeFile', {'folder': folder, 'name': name, 'bytes': bytes, 'mime': mime}))!;

  static Future<List<BackupFolderEntry>> listFiles(String folder) async {
    final raw = await _ch.invokeListMethod<Map<Object?, Object?>>('listFiles', {'folder': folder}) ?? const [];
    return [
      for (final m in raw)
        BackupFolderEntry(
          m['id'] as String,
          m['name'] as String,
          DateTime.fromMillisecondsSinceEpoch((m['modified'] as num?)?.toInt() ?? 0),
          (m['size'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  /// «Сохранить как»: системный диалог, человек выбирает место и имя файла. false — сохранение отменено.
  static Future<bool> saveAs(String name, Uint8List bytes, {String mime = 'application/octet-stream'}) async =>
      await _ch.invokeMethod<bool>('saveAs', {'name': name, 'bytes': bytes, 'mime': mime}) ?? false;

  static Future<void> deleteFile(String folder, String id) => _ch.invokeMethod<void>('deleteFile', {'folder': folder, 'id': id});
}
