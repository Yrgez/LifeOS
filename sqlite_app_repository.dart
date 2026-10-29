import 'dart:async';
import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../core/app_log.dart';
import '../models/models.dart';
import 'app_data.dart';
import 'app_repository.dart';
import 'change_set.dart';

/// Версия SQL-схемы (PRAGMA user_version). Менять при изменении таблиц и добавлять шаг в [_onUpgrade].
/// Не путать с [kSchemaVersion] — это версия формата JSON (резервные копии, поля AppData).
const int kDbVersion = 1;

/// Хранилище в SQLite.
///
/// * Крупные журналы — отдельные таблицы с индексами: `workout_sets`, `money_tx`.
/// * Небольшие списки (мышцы, цели, узлы графа…) — таблица `docs` (коллекция, id, позиция, JSON).
/// * Скаляры и недельные истории — таблица `kv`.
///
/// Запись **инкрементальная** на двух уровнях:
/// * журналы пишутся строго по [ChangeSet] от контроллера — без обхода и сериализации всех записей;
/// * небольшие коллекции и скаляры сравниваются с отпечатками последнего записанного состояния —
///   в одной транзакции пишутся только изменившиеся строки.
///
/// Без [ChangeSet] (или с `full`) журналы переписываются целиком — это нужно после импорта, сброса,
/// миграции и ошибки записи, когда точный перечень изменений неизвестен.
class SqliteAppRepository implements AppRepository {
  /// [opener] — как открыть базу (в приложении — файл `life_os.db`, в тестах — база в памяти).
  /// [legacy] — прежнее хранилище (SharedPreferences): при первом запуске данные из него переезжают в SQLite.
  /// Старые данные не удаляются — можно откатиться на предыдущую версию приложения.
  SqliteAppRepository({required this.opener, this.legacy});

  final Future<Database> Function() opener;
  final AppRepository? legacy;

  Database? _db;
  Future<void> _tail = Future<void>.value(); // очередь записей: сохранения выполняются строго по одному

  // Отпечатки последнего записанного состояния малых данных. Для журналов отпечатки не нужны.
  Map<String, String> _kvSnap = {};
  Map<String, String> _docSnap = {};

  static const _kvKeys = [
    'netWorth', 'monthlyIncome', 'monthlyExpense', 'dailySteps', 'activeCalories', 'proteinGrams', 'lastDay',
    'healthEnabled', 'lastHealthSyncMs', 'stepsWeekHistory', 'caloriesWeekHistory', 'graphEvolutionHistory',
    'userName', 'stepsGoal', 'proteinGoal', 'onboardingDone',
  ];

  static const _listCollections = ['goals', 'achievements', 'salaryHistory', 'graphNodes', 'graphEdges', 'recurring'];

  // ---------------- открытие и схема ----------------

  /// Открывает (создаёт) базу через фабрику без шифрования. Для SQLCipher см. `data/sqlcipher_opener.dart`:
  /// он использует те же колбэки схемы.
  static Future<Database> openDb(DatabaseFactory factory, String path) {
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: kDbVersion,
        onCreate: onCreateSchema,
        onUpgrade: onUpgradeSchema,
        onDowngrade: onDowngradeSchema,
      ),
    );
  }

  /// Таблицы схемы. Миграция шифрования копирует именно их: новая таблица обязана попасть сюда.
  static const tables = ['kv', 'docs', 'workout_sets', 'money_tx'];

  // база новее приложения: ничего не трогаем, контроллер переходит в режим «только чтение»
  static Future<void> onDowngradeSchema(Database db, int oldVersion, int newVersion) =>
      throw SchemaTooNewException(oldVersion);

  static Future<void> onCreateSchema(Database db, int version) async {
    await db.execute('CREATE TABLE kv (k TEXT PRIMARY KEY, v TEXT NOT NULL)');
    await db.execute('CREATE TABLE docs (coll TEXT NOT NULL, id TEXT NOT NULL, pos INTEGER NOT NULL, body TEXT NOT NULL, PRIMARY KEY (coll, id))');
    await db.execute('''
      CREATE TABLE workout_sets (
        id TEXT PRIMARY KEY,
        muscle_id TEXT NOT NULL,
        ts INTEGER NOT NULL,
        weight REAL NOT NULL,
        reps INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_sets_ts ON workout_sets (ts)');
    await db.execute('CREATE INDEX idx_sets_muscle ON workout_sets (muscle_id, ts)');
    await db.execute('''
      CREATE TABLE money_tx (
        id TEXT PRIMARY KEY,
        ts INTEGER NOT NULL,
        is_income INTEGER NOT NULL,
        amount INTEGER NOT NULL,
        category_id TEXT NOT NULL,
        note TEXT NOT NULL,
        affects_net_worth INTEGER NOT NULL,
        recurring_id TEXT
      )''');
    await db.execute('CREATE INDEX idx_tx_ts ON money_tx (ts)');
    await db.execute('CREATE INDEX idx_tx_category ON money_tx (category_id, ts)');
  }

  static Future<void> onUpgradeSchema(Database db, int oldVersion, int newVersion) async {
    // Шаги миграции добавлять сюда: if (oldVersion < 2) { await db.execute('ALTER TABLE ...'); }
  }

  Future<Database> _open() async => _db ??= await opener();

  Future<void> close() async {
    await _tail;
    await _db?.close();
    _db = null;
  }

  /// Выполняет [action] при закрытой базе и остановленной очереди сохранений (смена шифрования, сброс).
  /// Сохранения, вызванные во время действия, подождут и выполнятся после него; база откроется заново через [opener]
  /// (с актуальным ключом). Отпечатки малых данных остаются верными: содержимое базы не меняется.
  Future<T> exclusive<T>(Future<T> Function() action) {
    final run = _tail.then((_) async {
      await _db?.close();
      _db = null;
      return action();
    });
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  // ---------------- чтение ----------------

  @override
  Future<AppData?> load() async {
    final sw = Stopwatch()..start();
    final db = await _open();
    final init = await db.query('kv', where: 'k = ?', whereArgs: ['initialized']);

    if (init.isEmpty) {
      // База пуста: первый запуск или переезд из SharedPreferences.
      final old = await legacy?.load(); // исключение здесь = режим «только чтение», база не трогается
      if (old == null) return null;
      AppLog.d('Миграция данных из SharedPreferences в SQLite');
      _resetSnapshots();
      await save(old); // без ChangeSet — журналы пишутся целиком
      return old;
    }

    final j = await _readAll(db);
    final v = (j['schemaVersion'] as num?)?.toInt() ?? 1;
    if (v > kSchemaVersion) throw SchemaTooNewException(v);
    final data = AppData.fromJson(j);
    _snapshotFrom(data.toJson(includeLogs: false));
    AppLog.d('SQLite: загрузка — ${data.workoutSets.length} подходов, ${data.transactions.length} операций, ${sw.elapsedMilliseconds} мс');
    return data;
  }

  Future<Map<String, dynamic>> _readAll(Database db) async {
    final j = <String, dynamic>{};

    dynamic dec(String raw, String what) {
      try {
        return jsonDecode(raw);
      } catch (e, st) {
        AppLog.e('SQLite: повреждена запись «$what», пропущена', e, st);
        return null;
      }
    }

    for (final r in await db.query('kv')) {
      final k = r['k'] as String;
      final value = dec(r['v'] as String, 'kv:$k');
      if (value != null) j[k] = value;
    }

    // Все коллекции базы — «записаны»: пустая коллекция остаётся пустой (а не заменяется значениями по умолчанию).
    final muscles = <String, dynamic>{};
    final budgets = <String, dynamic>{};
    final lists = {for (final c in _listCollections) c: <dynamic>[]};
    for (final r in await db.query('docs', orderBy: 'coll, pos')) {
      final coll = r['coll'] as String;
      final id = r['id'] as String;
      final body = dec(r['body'] as String, '$coll:$id');
      if (body == null) continue;
      if (coll == 'muscles') {
        muscles[id] = body;
      } else if (coll == 'budgets') {
        budgets[id] = (body as Map)['v'];
      } else if (lists.containsKey(coll)) {
        lists[coll]!.add(body);
      }
    }
    j['muscles'] = muscles;
    j['budgets'] = budgets;
    j.addAll(lists);

    j['workoutSets'] = [
      for (final r in await db.query('workout_sets', orderBy: 'ts, id'))
        {'id': r['id'], 'm': r['muscle_id'], 't': r['ts'], 'w': r['weight'], 'r': r['reps']},
    ];
    j['transactions'] = [
      for (final r in await db.query('money_tx', orderBy: 'ts, id'))
        {
          'id': r['id'],
          't': r['ts'],
          'in': r['is_income'] == 1,
          'a': r['amount'],
          'c': r['category_id'],
          'n': r['note'],
          'nw': r['affects_net_worth'] == 1,
          'rid': r['recurring_id'],
        },
    ];
    return j;
  }

  // ---------------- запись ----------------

  @override
  Future<void> save(AppData data, {ChangeSet? changes}) {
    // Сохранения идут по очереди: параллельные вызовы не должны сравнивать состояние с одним и тем же
    // «старым» отпечатком — иначе возможна рассинхронизация таблиц и отпечатков.
    final run = _tail.then((_) => _saveNow(data, changes));
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _saveNow(AppData data, ChangeSet? changes) async {
    final sw = Stopwatch()..start();
    final db = await _open();
    final j = data.toJson(includeLogs: false); // журналы не сериализуем: они пишутся по ChangeSet

    final kv = _kvFrom(j);
    final docs = _docsFrom(j);
    final full = changes == null || changes.full;
    var logOps = 0;

    await db.transaction((txn) async {
      final b = txn.batch();

      kv.forEach((k, v) {
        if (_kvSnap[k] != v) b.insert('kv', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);
      });
      for (final k in _kvSnap.keys) {
        if (!kv.containsKey(k)) b.delete('kv', where: 'k = ?', whereArgs: [k]);
      }

      docs.forEach((key, d) {
        if (_docSnap[key] != d.fp) {
          b.insert('docs', {'coll': d.coll, 'id': d.id, 'pos': d.pos, 'body': d.body}, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      for (final key in _docSnap.keys) {
        if (!docs.containsKey(key)) {
          final parts = key.split('\u0001');
          b.delete('docs', where: 'coll = ? AND id = ?', whereArgs: [parts[0], parts.sublist(1).join('\u0001')]);
        }
      }

      if (full) {
        // Точный перечень изменений неизвестен — журналы переписываются целиком.
        b.delete('workout_sets');
        b.delete('money_tx');
        for (final s in data.workoutSets) {
          b.insert('workout_sets', _setRow(s), conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final t in data.transactions) {
          b.insert('money_tx', _txRow(t), conflictAlgorithm: ConflictAlgorithm.replace);
        }
        logOps = data.workoutSets.length + data.transactions.length;
      } else {
        for (final id in changes.setDeletes) {
          b.delete('workout_sets', where: 'id = ?', whereArgs: [id]);
        }
        for (final s in changes.setUpserts.values) {
          b.insert('workout_sets', _setRow(s), conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final id in changes.txDeletes) {
          b.delete('money_tx', where: 'id = ?', whereArgs: [id]);
        }
        for (final t in changes.txUpserts.values) {
          b.insert('money_tx', _txRow(t), conflictAlgorithm: ConflictAlgorithm.replace);
        }
        logOps = changes.setDeletes.length + changes.setUpserts.length + changes.txDeletes.length + changes.txUpserts.length;
      }

      await b.commit(noResult: true);
    });

    // Отпечатки обновляются только после успешной фиксации транзакции: при ошибке следующая запись повторит изменения.
    _kvSnap = kv;
    _docSnap = {for (final e in docs.entries) e.key: e.value.fp};

    if (full || sw.elapsedMilliseconds >= 50) {
      AppLog.d('SQLite: сохранение (${full ? 'полное' : 'точечное'}) — строк журналов: $logOps, ${sw.elapsedMilliseconds} мс');
    }
  }

  void _resetSnapshots() {
    _kvSnap = {};
    _docSnap = {};
  }

  void _snapshotFrom(Map<String, dynamic> j) {
    _kvSnap = _kvFrom(j);
    _docSnap = {for (final e in _docsFrom(j).entries) e.key: e.value.fp};
  }

  // ---------------- преобразование данных ⇄ строки таблиц ----------------

  static Map<String, Object?> _setRow(WorkoutSet s) => {
        'id': s.id,
        'muscle_id': s.muscleId,
        'ts': s.at.millisecondsSinceEpoch,
        'weight': s.weight,
        'reps': s.reps,
      };

  static Map<String, Object?> _txRow(MoneyTx t) => {
        'id': t.id,
        'ts': t.at.millisecondsSinceEpoch,
        'is_income': t.isIncome ? 1 : 0,
        'amount': t.amount,
        'category_id': t.categoryId,
        'note': t.note,
        'affects_net_worth': t.affectsNetWorth ? 1 : 0,
        'recurring_id': t.recurringId,
      };

  Map<String, String> _kvFrom(Map<String, dynamic> j) => {
        'initialized': '1',
        'schemaVersion': jsonEncode(j['schemaVersion']),
        for (final k in _kvKeys) k: jsonEncode(j[k]),
      };

  Map<String, _Doc> _docsFrom(Map<String, dynamic> j) {
    final out = <String, _Doc>{};
    void add(String coll, String id, int pos, Object? body) {
      out['$coll\u0001$id'] = _Doc(coll, id, pos, jsonEncode(body));
    }

    int pos = 0;
    for (final e in (j['muscles'] as Map<String, dynamic>).entries) {
      add('muscles', e.key, pos++, e.value);
    }
    pos = 0;
    for (final e in (j['budgets'] as Map<String, dynamic>).entries) {
      add('budgets', e.key, pos++, {'v': e.value});
    }

    String idOf(String coll, Map<String, dynamic> m, int i) {
      switch (coll) {
        case 'salaryHistory':
          return '$i'; // у точек зарплаты нет id — ключом служит позиция
        case 'graphEdges':
          return '${m['fromId']}>${m['toId']}';
        default:
          return '${m['id']}';
      }
    }

    for (final coll in _listCollections) {
      final list = j[coll] as List;
      for (int i = 0; i < list.length; i++) {
        final m = list[i] as Map<String, dynamic>;
        add(coll, idOf(coll, m, i), i, m);
      }
    }
    return out;
  }
}

class _Doc {
  final String coll;
  final String id;
  final int pos;
  final String body;
  _Doc(this.coll, this.id, this.pos, this.body);
  String get fp => '$pos|$body';
}
