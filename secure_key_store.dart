import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_store.dart';

/// Единственный файл, который знает о плагине `flutter_secure_storage` (pubspec: `^9.2.2`).
class SecureKeyStore implements KeyStore {
  final FlutterSecureStorage _s = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<String?> read(String name) => _s.read(key: name);

  @override
  Future<void> write(String name, String value) => _s.write(key: name, value: value);

  @override
  Future<void> delete(String name) => _s.delete(key: name);
}
