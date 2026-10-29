import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show compute;

class BackupDecryptException implements Exception {
  final String message;
  const BackupDecryptException(this.message);
  @override
  String toString() => message;
}

/// Шифрование резервных копий паролем: PBKDF2-HMAC-SHA256 → AES-256-GCM.
/// Формат — JSON (удобно копировать в буфер обмена): параметры шифрования лежат рядом с данными,
/// а заголовок (формат, версия, число итераций) защищён как дополнительные аутентифицируемые данные.
class BackupCipher {
  const BackupCipher({this.iterations = defaultIterations, this.useIsolate = false});

  static const format = 'lifeos-backup';
  static const version = 1;
  static const kdfName = 'pbkdf2-sha256';

  /// Достаточно, чтобы заметно замедлить перебор, и приемлемо по времени на телефоне (чистый Dart).
  /// Значение хранится в самой копии — позже можно увеличить без потери совместимости.
  static const defaultIterations = 150000;
  static const minPassphraseLength = 8;
  static const _maxAcceptedIterations = 2000000; // защита от «копий-ловушек» с огромной стоимостью разбора

  final int iterations;

  /// Выполнять тяжёлое вычисление ключа в отдельном изоляте (в приложении — да, чтобы не замирал интерфейс).
  final bool useIsolate;

  /// Это зашифрованная копия (а не обычный JSON)?
  static bool looksEncrypted(String text) {
    try {
      final j = jsonDecode(text);
      return j is Map && j['format'] == format;
    } catch (_) {
      return false;
    }
  }

  Future<String> encrypt(String plain, String passphrase) {
    if (passphrase.length < minPassphraseLength) {
      throw ArgumentError('Пароль короче $minPassphraseLength символов');
    }
    return useIsolate ? compute(_encryptJob, <Object>[plain, passphrase, iterations]) : _encryptCore(plain, passphrase, iterations);
  }

  Future<String> decrypt(String text, String passphrase) {
    return useIsolate ? compute(_decryptJob, <Object>[text, passphrase]) : _decryptCore(text, passphrase);
  }

  // ---------------- ядро ----------------

  static List<int> _randomBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  static List<int> _aad(int iterations) => utf8.encode('$format|$version|$kdfName|$iterations');

  static Future<SecretKey> _derive(String passphrase, List<int> salt, int iterations) {
    return Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256).deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  static Future<String> _encryptCore(String plain, String passphrase, int iterations) async {
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final key = await _derive(passphrase, salt, iterations);
    final box = await AesGcm.with256bits().encrypt(utf8.encode(plain), secretKey: key, nonce: nonce, aad: _aad(iterations));
    return jsonEncode({
      'format': format,
      'v': version,
      'kdf': kdfName,
      'iter': iterations,
      'salt': base64.encode(salt),
      'nonce': base64.encode(nonce),
      'ct': base64.encode(box.cipherText),
      'mac': base64.encode(box.mac.bytes),
    });
  }

  static Future<String> _decryptCore(String text, String passphrase) async {
    final Map<String, dynamic> j;
    try {
      final d = jsonDecode(text);
      if (d is! Map<String, dynamic> || d['format'] != format) throw const FormatException('не копия Life OS');
      j = d;
    } catch (_) {
      throw const BackupDecryptException('Это не зашифрованная копия Life OS');
    }
    if (j['v'] != version || j['kdf'] != kdfName) {
      throw const BackupDecryptException('Копия создана другой версией приложения');
    }
    final iter = j['iter'];
    if (iter is! int || iter < 1000 || iter > _maxAcceptedIterations) {
      throw const BackupDecryptException('Повреждён заголовок копии');
    }
    try {
      final salt = base64.decode(j['salt'] as String);
      final nonce = base64.decode(j['nonce'] as String);
      final ct = base64.decode(j['ct'] as String);
      final mac = base64.decode(j['mac'] as String);
      final key = await _derive(passphrase, salt, iter);
      final clear = await AesGcm.with256bits().decrypt(SecretBox(ct, nonce: nonce, mac: Mac(mac)), secretKey: key, aad: _aad(iter));
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      throw const BackupDecryptException('Неверный пароль или копия повреждена');
    } catch (_) {
      throw const BackupDecryptException('Неверный пароль или копия повреждена');
    }
  }
}

Future<String> _encryptJob(List<Object> a) => BackupCipher._encryptCore(a[0] as String, a[1] as String, a[2] as int);
Future<String> _decryptJob(List<Object> a) => BackupCipher._decryptCore(a[0] as String, a[1] as String);
