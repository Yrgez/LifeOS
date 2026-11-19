part of '../app_controller.dart';

/// Деньги: счета, операции, бюджеты, повторяющиеся операции.
/// Расширение того же library: работает с состоянием контроллера напрямую, мутации — только через `_commit`.
extension FinanceOps on AppController {
  // ---------------- счета ----------------

  List<Account> get accounts => List.unmodifiable(_d.accounts);

  /// Новый счёт с начальным остатком на дату [at] (по умолчанию — сейчас). Возвращает id или null.
  String? addAccount(String name, int balance, {DateTime? at}) {
    final n = name.trim();
    final now = _clock();
    final when = at ?? now;
    if (n.isEmpty || n.length > Account.maxName || when.isAfter(now.add(const Duration(minutes: 5))) || _d.accounts.length >= 200) return null;
    final a = Account(id: 'acc_${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}', name: n, history: [BalanceSnapshot(when, balance)]);
    _commit(() => _d.accounts.add(a));
    return a.id;
  }

  /// Новый снимок остатка (прежние сохраняются). Дата — не раньше последнего снимка и не в будущем.
  bool setAccountBalance(String id, int balance, {DateTime? at}) {
    final i = _d.accounts.indexWhere((a) => a.id == id);
    final now = _clock();
    final when = at ?? now;
    if (i < 0 || when.isAfter(now.add(const Duration(minutes: 5)))) return false;
    final a = _d.accounts[i];
    if (when.isBefore(a.latest.at) || a.history.length >= Account.maxHistory) return false;
    _commit(() => a.history.add(BalanceSnapshot(when, balance)));
    return true;
  }

  bool renameAccount(String id, String name) {
    final n = name.trim();
    final i = _d.accounts.indexWhere((a) => a.id == id);
    if (i < 0 || n.isEmpty || n.length > Account.maxName) return false;
    _commit(() => _d.accounts[i].name = n);
    return true;
  }

  /// Удаляет счёт вместе с историей (явное действие с подтверждением в интерфейсе).
  bool removeAccount(String id) {
    final i = _d.accounts.indexWhere((a) => a.id == id);
    if (i < 0) return false;
    _commit(() => _d.accounts.removeAt(i));
    return true;
  }

  // ---------------- финансы ----------------

  /// Капитал правится вручную, только пока счетов нет; доход и расходы здесь — плановые.
  void updateWealth({int? netWorth, int? income, int? expense}) => _commit(() {
        if (netWorth != null && _d.accounts.isEmpty) _d.netWorth = netWorth;
        if (income != null) _d.monthlyIncome = max(0, income);
        if (expense != null) _d.monthlyExpense = max(0, expense);
      });

  bool addSalaryStep(String year, String role, int salary) {
    if (year.trim().isEmpty || salary <= 0) return false;
    _commit(() => _d.salaryHistory.add(SalaryStep(year: year.trim(), role: role.trim(), salary: salary)));
    return true;
  }

  bool updateSalaryStep(int index, String year, String role, int salary) {
    if (index < 0 || index >= _d.salaryHistory.length || year.trim().isEmpty || salary <= 0) return false;
    _commit(() => _d.salaryHistory[index] = SalaryStep(year: year.trim(), role: role.trim(), salary: salary));
    return true;
  }

  /// Удаляет точку и возвращает её (для «Отменить»).
  SalaryStep? removeSalaryStep(int index) {
    if (index < 0 || index >= _d.salaryHistory.length) return null;
    late SalaryStep removed;
    _commit(() => removed = _d.salaryHistory.removeAt(index));
    return removed;
  }

  /// Возвращает точку на прежнее место.
  void insertSalaryStep(int index, SalaryStep step) {
    _commit(() => _d.salaryHistory.insert(clampI(index, 0, _d.salaryHistory.length), step));
  }

  // ---------------- финансы: операции ----------------

  /// Добавляет операцию. Тип (доход/расход) определяет категория. При [affectsNetWorth] чистый капитал
  /// меняется на сумму операции; удаление операции откатит ровно это изменение.
  bool addTransaction({
    required String categoryId,
    required int amount,
    DateTime? at,
    String note = '',
    bool affectsNetWorth = true,
  }) {
    final cat = finCategory(categoryId);
    if (cat == null || amount <= 0) return false;
    final tx = MoneyTx(
      id: 'tx_${_clock().microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}',
      at: at ?? _clock(),
      isIncome: cat.isIncome,
      amount: amount,
      categoryId: categoryId,
      note: note.trim(),
      affectsNetWorth: affectsNetWorth,
    );
    _commit(() => _insertTx(tx, applyNetWorth: true));
    return true;
  }

  /// Удаляет операцию и откатывает её влияние на капитал. Возвращает удалённую запись (для «Отменить»).
  MoneyTx? deleteTransaction(String id) {
    final i = _d.transactions.indexWhere((t) => t.id == id);
    if (i < 0) return null;
    late MoneyTx removed;
    _commit(() {
      removed = _d.transactions.removeAt(i);
      _pending.deleteTx(removed.id);
      if (removed.affectsNetWorth) _d.netWorth -= removed.signed;
    });
    return removed;
  }

  void restoreTransaction(MoneyTx tx) {
    if (_d.transactions.any((t) => t.id == tx.id)) return;
    _commit(() => _insertTx(tx, applyNetWorth: true));
  }

  /// Изменяет операцию. Влияние на капитал пересчитывается: старое откатывается, новое применяется.
  bool updateTransaction(
    String id, {
    required String categoryId,
    required int amount,
    required DateTime at,
    String note = '',
    required bool affectsNetWorth,
  }) {
    final i = _d.transactions.indexWhere((t) => t.id == id);
    final cat = finCategory(categoryId);
    if (i < 0 || cat == null || amount <= 0) return false;
    final old = _d.transactions[i];
    final updated = MoneyTx(
      id: old.id,
      at: at,
      isIncome: cat.isIncome,
      amount: amount,
      categoryId: categoryId,
      note: note.trim(),
      affectsNetWorth: affectsNetWorth,
      recurringId: old.recurringId,
      importId: old.importId,
    );
    _commit(() {
      if (old.affectsNetWorth) _d.netWorth -= old.signed;
      if (updated.affectsNetWorth) _d.netWorth += updated.signed;
      _d.transactions[i] = updated;
      _d.transactions.sort((a, b) => a.at.compareTo(b.at));
      _pending.upsertTx(updated);
    });
    return true;
  }

  // ---------------- импорт выписки ----------------

  List<StatementImport> get statementImports => List.unmodifiable(_d.imports);

  /// Сколько операций ещё помещается в журнал. Импорт сверх предела не выполняется: вытеснять старые
  /// операции ради новых нельзя.
  int get transactionCapacityLeft => _maxTx - _d.transactions.length;

  /// Сколько строк предпросмотра разберут правила.
  int statementRuleHits(List<StatementRow> rows) => rows.where((r) => categoryByRules(r.note, r.signed > 0, _d.importRules) != null).length;

  /// Частые описания списаний без правила — чтобы назначить категорию сразу из предпросмотра.
  List<(String, int)> statementUnmatched(List<StatementRow> rows) =>
      unmatchedPatterns([for (final r in rows) if (r.signed < 0) (r.note, false)], _d.importRules);

  /// Предпросмотр: что будет добавлено, что уже загружалось раньше, какие строки не распознаны.
  ({ParsedStatement parsed, List<StatementRow> fresh, List<StatementRow> duplicates}) previewStatement(String text, ColumnMapping mapping) {
    final parsed = parseStatement(text, mapping, now: _clock());
    final existing = [for (final t in _d.transactions) if (t.importId != null) statementFingerprint(t.at, t.signed, t.note)];
    final split = splitDuplicates(parsed.rows, existing);
    return (parsed: parsed, fresh: split.fresh, duplicates: split.duplicates);
  }

  /// Импортирует новые строки выписки как операции со ссылкой на импорт. Категории — общие для всех
  /// поступлений и списаний (поправить можно у каждой операции). [affectsNetWorth] по умолчанию выключен:
  /// капитал обычно уже учитывает прошлые траты. Возвращает id импорта или null (нечего добавить, не помещается,
  /// неверные категории или название).
  String? importStatement(
    String text,
    ColumnMapping mapping, {
    required String name,
    String expenseCategory = 'other_exp',
    String incomeCategory = 'other_inc',
    bool affectsNetWorth = false,
  }) {
    final exp = finCategory(expenseCategory), inc = finCategory(incomeCategory);
    final n = name.trim();
    if (exp == null || exp.isIncome || inc == null || !inc.isIncome || n.isEmpty || n.length > StatementImport.maxName) return null;
    final p = previewStatement(text, mapping);
    if (p.fresh.isEmpty || p.fresh.length > transactionCapacityLeft || _d.imports.length >= 5000) return null;
    final now = _clock();
    final id = 'imp_${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}';
    _commit(() {
      for (var k = 0; k < p.fresh.length; k++) {
        final r = p.fresh[k];
        _insertTx(
          MoneyTx(
            id: 'tx_${now.microsecondsSinceEpoch}_${k}_${_random.nextInt(1 << 20)}',
            at: r.at,
            isIncome: r.signed > 0,
            amount: r.signed.abs(),
            // правила человека — первыми; не подошло ни одно — категория по умолчанию
            categoryId: categoryByRules(r.note, r.signed > 0, _d.importRules) ?? (r.signed > 0 ? incomeCategory : expenseCategory),
            note: r.note,
            affectsNetWorth: affectsNetWorth,
            importId: id,
          ),
          applyNetWorth: true,
        );
      }
      _d.imports.add(StatementImport(id: id, at: now, name: n, added: p.fresh.length, duplicates: p.duplicates.length, rejected: p.parsed.rejected.length));
    });
    return id;
  }

  /// Отмена импорта: его операции удаляются (влияние на капитал откатывается), запись импорта остаётся
  /// с пометкой времени отмены. Явное действие с подтверждением в интерфейсе.
  int? undoImport(String importId) {
    final imp = _d.imports.where((x) => x.id == importId).firstOrNull;
    if (imp == null || imp.undoneAt != null) return null;
    var removed = 0;
    _commit(() {
      _d.transactions.removeWhere((t) {
        if (t.importId != importId) return false;
        _pending.deleteTx(t.id);
        if (t.affectsNetWorth) _d.netWorth -= t.signed;
        removed++;
        return true;
      });
      imp.undoneAt = _clock();
    });
    return removed;
  }

  // ---------------- бюджеты ----------------

  Map<String, int> get budgets => Map.unmodifiable(_d.budgets);

  /// Лимит расходов на месяц по категории; [limit] ≤ 0 снимает лимит. Только для категорий расходов.
  bool setBudget(String categoryId, int limit) {
    final cat = finCategory(categoryId);
    if (cat == null || cat.isIncome) return false;
    _commit(() {
      if (limit > 0) {
        _d.budgets[categoryId] = limit;
      } else {
        _d.budgets.remove(categoryId);
      }
    });
    return true;
  }

  // ---------------- повторяющиеся операции ----------------

  List<RecurringTx> get recurring => List.unmodifiable(_d.recurring);

  /// Создаёт правило. Операции создаются автоматически, начиная с ближайшей даты не раньше сегодняшнего дня.
  bool addRecurring({
    required String categoryId,
    required int amount,
    required int dayOfMonth,
    String note = '',
    bool affectsNetWorth = true,
  }) {
    if (finCategory(categoryId) == null || amount <= 0 || dayOfMonth < 1 || dayOfMonth > 31) return false;
    _commit(() {
      _d.recurring.add(RecurringTx(
        id: 'rec_${_clock().microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}',
        categoryId: categoryId,
        amount: amount,
        dayOfMonth: dayOfMonth,
        note: note.trim(),
        affectsNetWorth: affectsNetWorth,
        start: dateOnly(_clock()),
      ));
      _generateRecurring();
    });
    return true;
  }

  /// Изменяет правило. Новые значения действуют на ещё не созданные операции; уже созданные не меняются,
  /// обработанные месяцы повторно не создаются. Дата начала правила сохраняется.
  bool updateRecurring(
    String id, {
    required String categoryId,
    required int amount,
    required int dayOfMonth,
    String note = '',
    required bool affectsNetWorth,
  }) {
    final i = _d.recurring.indexWhere((r) => r.id == id);
    if (i < 0 || finCategory(categoryId) == null || amount <= 0 || dayOfMonth < 1 || dayOfMonth > 31) return false;
    final old = _d.recurring[i];
    _commit(() {
      _d.recurring[i] = RecurringTx(
        id: old.id,
        categoryId: categoryId,
        amount: amount,
        dayOfMonth: dayOfMonth,
        note: note.trim(),
        affectsNetWorth: affectsNetWorth,
        start: old.start,
        lastMonth: old.lastMonth,
      );
      _generateRecurring(); // новое число могло «наступить» уже сегодня
    });
    return true;
  }

  /// Удаляет правило; уже созданные им операции остаются.
  void removeRecurring(String id) => _commit(() => _d.recurring.removeWhere((r) => r.id == id));

  /// Создаёт наступившие операции по правилам. Идемпотентно: месяц, уже обработанный правилом
  /// (`lastMonth`), повторно не создаётся — даже если операцию потом удалили вручную.
  void _generateRecurring() {
    final today = dateOnly(_clock());
    final thisMonth = DateTime(today.year, today.month, 1);
    for (final r in _d.recurring) {
      final cat = finCategory(r.categoryId);
      if (cat == null) continue;
      var month = parseYm(r.lastMonth) == null ? DateTime(r.start.year, r.start.month, 1) : addMonths(parseYm(r.lastMonth)!, 1);
      int guard = 0;
      while (!month.isAfter(thisMonth) && guard++ < 60) {
        final due = DateTime(month.year, month.month, min(r.dayOfMonth, daysInMonth(month)));
        if (due.isAfter(today)) break; // срок ещё не наступил — вернёмся позже
        final id = 'rec_${r.id}_${ymKey(month)}';
        if (!due.isBefore(r.start) && !_d.transactions.any((t) => t.id == id)) {
          _insertTx(
            MoneyTx(
              id: id,
              at: DateTime(due.year, due.month, due.day, 9),
              isIncome: cat.isIncome,
              amount: r.amount,
              categoryId: r.categoryId,
              note: r.note,
              affectsNetWorth: r.affectsNetWorth,
              recurringId: r.id,
            ),
            applyNetWorth: true,
          );
        }
        r.lastMonth = ymKey(month);
        month = addMonths(month, 1);
      }
    }
  }

  void _insertTx(MoneyTx tx, {required bool applyNetWorth}) {
    _d.transactions.add(tx);
    _d.transactions.sort((a, b) => a.at.compareTo(b.at));
    _pending.upsertTx(tx);
    if (applyNetWorth && tx.affectsNetWorth) _d.netWorth += tx.signed;
    if (_d.transactions.length > _maxTx) {
      final drop = _d.transactions.length - _maxTx;
      final dropped = _d.transactions.take(drop).toList();
      _d.transactions.removeRange(0, drop); // капитал не трогаем: старые операции уже учтены в нём
      for (final x in dropped) {
        _pending.deleteTx(x.id);
      }
      AppLog.e('Список операций превысил $_maxTx — удалено старейших: $drop');
    }
  }
}
