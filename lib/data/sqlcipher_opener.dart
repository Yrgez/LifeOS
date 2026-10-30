import 'package:sqflite_sqlcipher/sqflite.dart';

import 'sqlite_app_repository.dart';

/// Единственное место, где база открывается через плагин `sqflite_sqlcipher`.
/// [password] == null — обычная (нешифрованная) база; иначе — SQLCipher с этим ключом.
/// Если API форка изменится — правится только этот файл.
Future<Database> openSqlCipher(String path, {String? password}) {
  return openDatabase(
    path,
    password: password,
    version: kDbVersion,
    onCreate: SqliteAppRepository.onCreateSchema,
    onUpgrade: SqliteAppRepository.onUpgradeSchema,
    onDowngrade: SqliteAppRepository.onDowngradeSchema,
  );
}
