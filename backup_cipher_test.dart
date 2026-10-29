import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/security/backup_cipher.dart';
import 'package:life_os/state/app_controller.dart';

void main() {
  // небольшое число итераций — тесты быстрые; в приложении по умолчанию 150 000
  const cipher = BackupCipher(iterations: 1000);
  const pass = 'правильный пароль 123';

  group('шифрование и расшифровка', () {
    test('круг: расшифровка возвращает исходный текст', () async {
      const text = '{"a": 1, "b": "кириллица и эмодзи 🙂"}';
      final enc = await cipher.encrypt(text, pass);
      expect(enc, isNot(contains('кириллица')));
      expect(await cipher.decrypt(enc, pass), text);
    });

    test('большая копия', () async {
      final big = jsonEncode({'data': List.generate(20000, (i) => 'запись $i')});
      final enc = await cipher.encrypt(big, pass);
      expect(await cipher.decrypt(enc, pass), big);
    });

    test('каждое шифрование даёт разный результат (случайные соль и nonce)', () async {
      final a = await cipher.encrypt('текст', pass);
      final b = await cipher.encrypt('текст', pass);
      expect(a, isNot(b));
    });

    test('в заголовке указаны формат и число итераций', () async {
      final j = jsonDecode(await cipher.encrypt('x', pass)) as Map<String, dynamic>;
      expect(j['format'], BackupCipher.format);
      expect(j['iter'], 1000);
      expect(j['kdf'], BackupCipher.kdfName);
    });

    test('копия с другим числом итераций читается (параметры берутся из самой копии)', () async {
      final enc = await const BackupCipher(iterations: 2000).encrypt('текст', pass);
      expect(await cipher.decrypt(enc, pass), 'текст');
    });

    test('в отдельном изоляте', () async {
      final iso = const BackupCipher(iterations: 1000, useIsolate: true);
      final enc = await iso.encrypt('в изоляте', pass);
      expect(await iso.decrypt(enc, pass), 'в изоляте');
    });
  });

  group('защита от ошибок и подмены', () {
    test('неверный пароль', () async {
      final enc = await cipher.encrypt('секрет', pass);
      await expectLater(cipher.decrypt(enc, 'другой пароль 999'), throwsA(isA<BackupDecryptException>()));
    });

    test('любое изменение шифртекста или метки обнаруживается', () async {
      final j = jsonDecode(await cipher.encrypt('секрет', pass)) as Map<String, dynamic>;
      for (final field in ['ct', 'mac', 'nonce', 'salt']) {
        final bytes = base64.decode(j[field] as String);
        bytes[0] ^= 0x01;
        final tampered = Map<String, dynamic>.of(j)..[field] = base64.encode(bytes);
        await expectLater(cipher.decrypt(jsonEncode(tampered), pass), throwsA(isA<BackupDecryptException>()), reason: field);
      }
    });

    test('подмена числа итераций в заголовке обнаруживается (заголовок аутентифицируется)', () async {
      final j = jsonDecode(await cipher.encrypt('секрет', pass)) as Map<String, dynamic>;
      j['iter'] = 1001;
      await expectLater(cipher.decrypt(jsonEncode(j), pass), throwsA(isA<BackupDecryptException>()));
    });

    test('«копия-ловушка» с огромным числом итераций отклоняется сразу', () async {
      final j = jsonDecode(await cipher.encrypt('x', pass)) as Map<String, dynamic>;
      j['iter'] = 2000000000;
      await expectLater(cipher.decrypt(jsonEncode(j), pass), throwsA(isA<BackupDecryptException>()));
      j['iter'] = 5;
      await expectLater(cipher.decrypt(jsonEncode(j), pass), throwsA(isA<BackupDecryptException>()));
    });

    test('чужая версия и не копия', () async {
      final j = jsonDecode(await cipher.encrypt('x', pass)) as Map<String, dynamic>;
      j['v'] = 99;
      await expectLater(cipher.decrypt(jsonEncode(j), pass), throwsA(isA<BackupDecryptException>()));
      await expectLater(cipher.decrypt('просто текст', pass), throwsA(isA<BackupDecryptException>()));
      await expectLater(cipher.decrypt('{"a":1}', pass), throwsA(isA<BackupDecryptException>()));
    });

    test('слишком короткий пароль отклоняется при шифровании', () {
      expect(() => cipher.encrypt('x', '1234567'), throwsArgumentError);
    });
  });

  group('определение формата', () {
    test('looksEncrypted', () async {
      expect(BackupCipher.looksEncrypted(await cipher.encrypt('x', pass)), isTrue);
      expect(BackupCipher.looksEncrypted('{"schemaVersion": 3}'), isFalse);
      expect(BackupCipher.looksEncrypted('не json'), isFalse);
      expect(BackupCipher.looksEncrypted('[1,2]'), isFalse);
    });
  });

  test('сквозной сценарий: экспорт → шифрование → расшифровка → импорт восстанавливает данные', () async {
    final a = AppController(MemoryAppRepository(), saveDelay: const Duration(days: 1));
    await a.load();
    a.logWorkout('chest', 100, 5);
    a.addTransaction(categoryId: 'salary', amount: 90000, note: 'аванс');
    final original = a.exportBackup();

    final enc = await cipher.encrypt(original, pass);
    expect(BackupCipher.looksEncrypted(enc), isTrue);

    final b = AppController(MemoryAppRepository(), saveDelay: const Duration(days: 1));
    await b.load();
    expect(b.importBackup(await cipher.decrypt(enc, pass)), isTrue);
    expect(b.sets.single.weight, 100);
    expect(b.transactions.single.note, 'аванс');
  });
}
