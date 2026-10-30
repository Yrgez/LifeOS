import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/data/sqlite_app_repository.dart';
import 'package:life_os/security/db_encryption.dart';
import 'package:life_os/security/key_store.dart';
import 'package:life_os/security/security_service.dart';

/// Менеджер-заглушка: записывает вызовы, поведение настраивается.
class _FakeManager extends DbEncryptionManager {
  _FakeManager()
      : super(open: (p, {String? password}) => throw UnimplementedError(), keys: MemoryKeyStore(), path: '/nonexistent', tables: SqliteAppRepository.tables);

  bool encrypted = false;
  Object? setError;
  Completer<void>? gate;
  final List<String> log = [];

  @override
  Future<bool> isEncrypted() async => encrypted;

  @override
  Future<void> setEncrypted(bool enable) async {
    log.add('set:$enable');
    await gate?.future;
    if (setError != null) throw setError!;
    encrypted = enable;
  }

  @override
  Future<void> destroy() async {
    log.add('destroy');
    encrypted = false;
  }
}

Future<T> _run<T>(Future<T> Function() a) => a();

void main() {
  late _FakeManager m;
  late List<String> order;

  SecurityService make({bool exclusive = true, Future<void> Function()? onReset}) {
    return SecurityService(
      lock: SecurityService.disabled().lock,
      encryption: m,
      flushStorage: () async => order.add('flush'),
      exclusive: exclusive ? _run : null,
      onStorageReset: onReset,
    );
  }

  setUp(() {
    m = _FakeManager();
    order = [];
  });

  test('без менеджера шифрование недоступно', () async {
    final s = SecurityService.disabled();
    expect(s.encryptionSupported, isFalse);
    final r = await s.setEncryption(true);
    expect(r.ok, isFalse);
  });

  test('сначала записываются накопленные изменения, затем выполняется смена', () async {
    final s = make();
    final r = await s.setEncryption(true);
    expect(r.ok, isTrue);
    expect(order, ['flush']);
    expect(m.log, ['set:true']);
    expect(s.encrypted, isTrue);
  });

  test('init читает текущее состояние', () async {
    m.encrypted = true;
    final s = make();
    await s.init();
    expect(s.encrypted, isTrue);
  });

  test('то же значение — ничего не делаем', () async {
    final s = make();
    final r = await s.setEncryption(false);
    expect(r.ok, isTrue);
    expect(m.log, isEmpty);
  });

  test('пока идёт смена, повторный запрос отклоняется; флаг busy снимается', () async {
    final s = make();
    m.gate = Completer<void>();
    final first = s.setEncryption(true);
    await Future<void>.delayed(Duration.zero);
    expect(s.busy, isTrue);
    final second = await s.setEncryption(true);
    expect(second.ok, isFalse);
    expect(second.message, contains('уже выполняется'));
    m.gate!.complete();
    expect((await first).ok, isTrue);
    expect(s.busy, isFalse);
  });

  test('ошибка миграции: понятное сообщение, состояние не меняется', () async {
    final s = make();
    m.setError = EncryptionException('Число строк не сошлось');
    final r = await s.setEncryption(true);
    expect(r.ok, isFalse);
    expect(r.message, contains('Число строк не сошлось'));
    expect(r.message, contains('Данные не изменены'));
    expect(s.encrypted, isFalse);
    expect(s.busy, isFalse);
  });

  test('непредвиденная ошибка тоже не роняет приложение', () async {
    final s = make();
    m.setError = StateError('что-то пошло не так');
    final r = await s.setEncryption(true);
    expect(r.ok, isFalse);
    expect(s.busy, isFalse);
  });

  test('без выполнения «в эксклюзивном режиме» шифрование не поддерживается (нельзя менять открытую базу)', () {
    expect(make(exclusive: false).encryptionSupported, isFalse);
  });

  test('сброс хранилища: удаляет базу и просит приложение начать заново', () async {
    var reset = 0;
    final s = make(onReset: () async => reset++);
    m.encrypted = true;
    await s.init();
    final r = await s.resetStorage();
    expect(r.ok, isTrue);
    expect(m.log, ['destroy']);
    expect(reset, 1);
    expect(s.encrypted, isFalse);
  });
}
