import 'dart:math';

/// Безопасное хранилище небольших секретов (ключ шифрования базы). В приложении — Android Keystore / iOS Keychain.
abstract class KeyStore {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
  Future<void> delete(String name);
}

class MemoryKeyStore implements KeyStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String name) async => data[name];

  @override
  Future<void> write(String name, String value) async => data[name] = value;

  @override
  Future<void> delete(String name) async => data.remove(name);
}

/// Случайный ключ базы: 32 байта в шестнадцатеричной записи (64 символа).
String generateDbKey({Random? random}) {
  final r = random ?? Random.secure();
  return List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
