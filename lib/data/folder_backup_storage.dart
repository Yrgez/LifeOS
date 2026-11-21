import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:backup_folder/backup_folder.dart';

import 'backup_storage.dart';

/// Папка для копий на Android (Storage Access Framework, локальный плагин `packages/backup_folder`).
class FolderBackupStorage implements BackupStorage {
  const FolderBackupStorage();

  /// На других платформах — заглушка: плагин реализован только для Android.
  static BackupStorage forPlatform() => Platform.isAndroid ? const FolderBackupStorage() : const UnsupportedBackupStorage();

  @override
  Future<String?> pickFolder() => BackupFolder.pickFolder();

  @override
  Future<bool> hasAccess(String folder) => BackupFolder.hasAccess(folder);

  @override
  Future<String?> folderName(String folder) => BackupFolder.folderName(folder);

  @override
  Future<void> write(String folder, String name, Uint8List bytes) => BackupFolder.writeFile(folder, name, bytes);

  @override
  Future<List<StoredBackup>> list(String folder) async => [for (final f in await BackupFolder.listFiles(folder)) StoredBackup(f.id, f.name)];

  @override
  Future<void> delete(String folder, String id) => BackupFolder.deleteFile(folder, id);

  @override
  Future<bool> saveAs(String name, Uint8List bytes, String mime) => BackupFolder.saveAs(name, bytes, mime: mime);
}
