import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_log.dart';
import '../../core/app_version.dart';
import '../../core/backup_schedule.dart';
import '../../core/currency.dart';
import '../../core/reminders.dart';
import '../../core/sections.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/app_data.dart';
import '../../security/app_lock.dart';
import '../../security/auto_backup.dart';
import '../../security/backup_cipher.dart';
import '../../security/biometric_authenticator.dart';
import '../../security/security_service.dart';
import '../../security/security_settings.dart';
import '../../state/app_controller.dart';
import '../../state/reminders.dart';
import '../widgets/adaptive_pair.dart';
import '../widgets/backup_actions.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';
import '../widgets/health_actions.dart';
import '../widgets/progress_dialog.dart';
import '../widgets/toast.dart';
import 'statement_import_screen.dart';

/// Настройки: профиль, цели дня, Health Connect, данные (резервная копия, примеры, сброс), о приложении.
class SettingsScreen extends StatefulWidget {
  final AppController controller;
  final SecurityService security;
  const SettingsScreen({super.key, required this.controller, required this.security});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppController get c => widget.controller;
  SecurityService get security => widget.security;
  AppLock get lock => widget.security.lock;

  // ---------------- действия ----------------

  Future<void> _editName() async {
    final r = await showFormDialog(
      context,
      title: 'Как к вам обращаться',
      actionLabel: 'Сохранить',
      fields: [FieldSpec('n', 'Имя (можно пусто)', initial: c.userName)],
    );
    if (r == null || !mounted) return;
    c.updateSettings(userName: r['n']);
  }

  Future<void> _editCurrency() async {
    final r = await showFormDialog(
      context,
      title: 'Основная валюта',
      actionLabel: 'Сохранить',
      fields: [
        FieldSpec('c', 'Валюта', initial: c.currency, options: {for (final x in currencies) x.code: '${x.symbol} — ${x.name}'}),
      ],
    );
    if (r == null || !mounted || r['c'] == c.currency) return;
    c.setCurrency(r['c']!);
    showToast(context, 'Обозначение сменилось на $cur. Суммы не пересчитываются — курс приложению неизвестен.');
  }

  Future<void> _copyExport(String what, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showToast(context, '$what — в буфере обмена. Вставьте в файл или таблицу');
  }

  Future<void> _editStepsGoal() async {
    final r = await showFormDialog(
      context,
      title: 'Цель по шагам на день',
      actionLabel: 'Сохранить',
      fields: [FieldSpec('v', 'Шагов в день', initial: '${c.stepsGoal}', numeric: true)],
      validate: (v) => (parseInt(v['v']!) ?? 0) >= 1 && (parseInt(v['v']!) ?? 0) <= 100000,
    );
    if (r == null || !mounted) return;
    c.updateSettings(stepsGoal: parseInt(r['v']!));
  }

  Future<void> _editProteinGoal() async {
    final r = await showFormDialog(
      context,
      title: 'Норма белка на день',
      actionLabel: 'Сохранить',
      fields: [FieldSpec('v', 'Граммов в день', initial: '${c.proteinGoal}', numeric: true)],
      validate: (v) => (parseInt(v['v']!) ?? 0) >= 1 && (parseInt(v['v']!) ?? 0) <= 1000,
    );
    if (r == null || !mounted) return;
    c.updateSettings(proteinGoal: parseInt(r['v']!));
  }

  // ---------------- напоминания ----------------

  Future<ReminderTime?> _pickTime(ReminderTime t) async {
    final r = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: t.hour, minute: t.minute),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    return r == null ? null : ReminderTime(r.hour, r.minute);
  }

  Widget _reminderRow(Reminders r, {required String id, required String title, required String hint, required bool on, required ReminderTime time,
      required ReminderPrefs Function(bool on, ReminderTime t) build}) {
    return SwitchListTile(
      key: ValueKey('reminder_$id'),
      value: on,
      onChanged: (v) => r.update(build(v, time)),
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text(hint, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          if (on)
            TextButton(
              key: ValueKey('reminder_${id}_time'),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 28)),
              onPressed: () async {
                final t = await _pickTime(time);
                if (t != null) await r.update(build(on, t));
              },
              child: Text('в ${time.label}'),
            ),
        ],
      ),
    );
  }

  List<Widget> _reminderTiles(Reminders r) {
    final p = r.prefs;
    final next = r.scheduled.isEmpty ? null : r.scheduled.first;
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text('Приглашения, а не оценки: о том, что уже сделано, не напомним. Всё работает на телефоне, без сети.',
            style: TextStyle(color: AppColors.muted, fontSize: 13)),
      ),
      _reminderRow(r,
          id: 'checkin',
          title: 'Отметка дня',
          hint: 'вечером, если день не отмечен',
          on: p.checkIn,
          time: p.checkInTime,
          build: (on, t) => ReminderPrefs(checkIn: on, checkInTime: t, bills: p.bills, billsTime: p.billsTime, review: p.review, reviewTime: p.reviewTime)),
      _reminderRow(r,
          id: 'bills',
          title: 'Сроки счетов',
          hint: 'накануне и в день оплаты',
          on: p.bills,
          time: p.billsTime,
          build: (on, t) => ReminderPrefs(checkIn: p.checkIn, checkInTime: p.checkInTime, bills: on, billsTime: t, review: p.review, reviewTime: p.reviewTime)),
      _reminderRow(r,
          id: 'review',
          title: 'Обзор недели',
          hint: 'когда пора',
          on: p.review,
          time: p.reviewTime,
          build: (on, t) => ReminderPrefs(checkIn: p.checkIn, checkInTime: p.checkInTime, bills: p.bills, billsTime: p.billsTime, review: on, reviewTime: t)),
      if (p.any && !r.permitted)
        ListTile(
          key: const ValueKey('reminders_denied'),
          leading: const Icon(Icons.notifications_off_outlined, color: AppColors.text, size: 20),
          title: const Text('Уведомления запрещены', style: TextStyle(fontSize: 13, color: AppColors.text)),
          subtitle: const Text('Разрешите их — или в настройках Android для LIFE OS', style: TextStyle(color: AppColors.muted, fontSize: 11)),
          trailing: TextButton(onPressed: r.requestPermission, child: const Text('Разрешить')),
        )
      else if (next != null)
        Padding(
          key: const ValueKey('reminders_next'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text('Ближайшее: ${fmtDate(next.at)} ${fmtTime(next.at)} — ${next.title}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ),
    ];
  }

  // ---------------- автоматическая резервная копия ----------------

  static const _intervalLabels = {1: 'ежедневно', 7: 'еженедельно', 30: 'ежемесячно'};

  Future<void> _backupPassword(AutoBackup b) async {
    final r = await showFormDialog(
      context,
      title: 'Пароль резервных копий',
      actionLabel: 'Сохранить',
      accent: AppColors.accent,
      fields: const [
        FieldSpec('p', 'Пароль (от ${BackupCipher.minPassphraseLength} символов)', obscure: true),
        FieldSpec('p2', 'Повторите пароль', obscure: true),
      ],
      validate: (v) => v['p']!.length >= BackupCipher.minPassphraseLength && v['p'] == v['p2'],
    );
    if (r == null || !mounted) return;
    await b.setPassword(r['p']!);
    if (mounted) showToast(context, 'Пароль сохранён. Запишите его: на новом телефоне без него копию не открыть');
  }

  Future<void> _backupNow(AutoBackup b) async {
    final r = await runWithProgress(context, 'Резервная копия…', b.runNow);
    if (!mounted) return;
    showToast(context, switch (r) {
      BackupOutcome.done => 'Копия записана: ${b.lastFile}',
      BackupOutcome.notConfigured => 'Сначала выберите папку и задайте пароль',
      BackupOutcome.noAccess => 'Нет доступа к папке — выберите её заново',
      BackupOutcome.failed => 'Копия не записана: ${b.error ?? 'ошибка'}',
    });
  }

  Future<void> _backupDisable(AutoBackup b) async {
    final ok = await confirmDialog(context,
        title: 'Отключить автокопию?',
        message: 'Приложение забудет папку и пароль копий. Уже сделанные копии останутся в папке.',
        confirmLabel: 'Отключить',
        danger: true);
    if (ok) await b.disable();
  }

  List<Widget> _backupTiles(AutoBackup? b) {
    final restore = _tile(Icons.settings_backup_restore, 'Восстановить из файла', 'Копия LIFE OS (в том числе автокопия); заменяет все данные',
        onTap: () => restoreFromFile(context, c, cipher: security.backupCipher));
    if (b == null || !b.supported) return [restore];
    final now = c.now;
    final days = daysSinceBackup(b.lastAt, now);
    final status = b.lastAt == null
        ? 'Копий ещё не было'
        : 'Последняя копия: ${fmtDate(b.lastAt!)} ${fmtTime(b.lastAt!)}${days != null && days > 0 ? ' ($days дн. назад)' : ''}';
    return [
      Padding(
        key: const ValueKey('backup_status'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Данные хранятся только на телефоне. Автокопия раз в выбранный срок кладёт зашифрованную копию в папку, '
              'которую вы укажете — например, в Google Drive. Хранятся последние $backupKeepCount копий.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(status, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            if (b.error != null) Text('Не получилось: ${b.error}', style: const TextStyle(color: AppColors.text, fontSize: 13)),
          ],
        ),
      ),
      _tile(Icons.folder_outlined, 'Папка для копий', b.folder == null ? 'Не выбрана' : (b.folderName ?? 'выбрана'),
          onTap: () async {
        final ok = await b.chooseFolder();
        if (ok && mounted && b.configured && b.lastAt == null) await _backupNow(b);
      }),
      _tile(Icons.password, 'Пароль копий', b.hasPassword ? 'Задан · хранится в защищённом хранилище телефона' : 'Не задан — без него копия не делается',
          onTap: () async {
        await _backupPassword(b);
        if (mounted && b.configured && b.lastAt == null) await _backupNow(b);
      }),
      _tile(
        Icons.schedule,
        'Как часто',
        'При открытии приложения',
        trailing: DropdownButton<int>(
          key: const ValueKey('backup_interval'),
          value: b.intervalDays,
          underline: const SizedBox.shrink(),
          items: [for (final d in backupIntervalOptions) DropdownMenuItem(value: d, child: Text(_intervalLabels[d]!))],
          onChanged: (v) => v == null ? null : b.setInterval(v),
        ),
      ),
      _tile(Icons.backup_outlined, 'Сделать копию сейчас', b.configured ? 'Записать копию в папку' : 'Нужны папка и пароль',
          onTap: b.configured && !b.running ? () => _backupNow(b) : null),
      restore,
      if (b.folder != null || b.hasPassword) _tile(Icons.cloud_off_outlined, 'Отключить автокопию', 'Забыть папку и пароль', onTap: () => _backupDisable(b)),
    ];
  }

  Future<void> _loadDemo() async {
    final ok = await confirmDialog(
      context,
      title: 'Загрузить примеры данных?',
      message: 'Журнал, операции, цели и граф будут заменены примерами. Имя, цели дня и подключение Health Connect сохранятся. '
          'Если нужны ваши текущие данные — сначала сделайте экспорт.',
      confirmLabel: 'Заменить',
      danger: true,
    );
    if (!ok || !mounted) return;
    c.resetAllData(demo: true);
    showToast(context, 'Загружены примеры данных');
  }

  Future<void> _reset() async {
    final r = await showFormDialog(
      context,
      title: 'Сбросить все данные',
      actionLabel: 'Сбросить',
      accent: AppColors.red,
      actionTextColor: Colors.white,
      fields: const [FieldSpec('w', 'Введите СБРОС для подтверждения')],
      validate: (v) => v['w']!.trim().toUpperCase() == 'СБРОС',
    );
    if (r == null || !mounted) return;
    c.resetAllData();
    showToast(context, 'Данные сброшены');
  }

  Future<void> _copyLog() async {
    final lines = AppLog.recent;
    await Clipboard.setData(ClipboardData(text: lines.isEmpty ? '(журнал пуст)' : lines.join('\n')));
    if (!mounted) return;
    showToast(context, 'Журнал диагностики скопирован');
  }

  void _restartOnboarding() {
    Navigator.of(context).pop(); // закрыть настройки: знакомство показывается поверх основной оболочки
    c.restartOnboarding();
  }

  // ---------------- безопасность ----------------

  Future<void> _toggleLock(bool value) async {
    final out = await lock.setEnabled(value);
    if (!mounted) return;
    switch (out) {
      case AuthOutcome.success:
        showToast(context, value ? 'Блокировка включена' : 'Блокировка отключена');
      case AuthOutcome.notAvailable:
        showToast(context, lock.message ?? 'Сначала настройте на устройстве биометрию или PIN');
      case AuthOutcome.lockedOut:
        showToast(context, 'Слишком много попыток. Подождите и повторите');
      case AuthOutcome.failed:
        showToast(context, 'Не удалось подтвердить личность');
      case AuthOutcome.cancelled:
        break;
    }
  }

  static String _timeoutLabel(int sec) {
    switch (sec) {
      case 0:
        return 'Сразу при выходе из приложения';
      case 30:
        return 'Через 30 секунд';
      case 60:
        return 'Через 1 минуту';
      case 300:
        return 'Через 5 минут';
      default:
        return '$sec с';
    }
  }

  Future<void> _pickTimeout() async {
    final r = await showFormDialog(
      context,
      title: 'Блокировать приложение',
      actionLabel: 'Сохранить',
      fields: [
        FieldSpec('t', 'После ухода в фон', initial: '${lock.timeoutSec}', options: {
          for (final t in SecuritySettings.timeoutOptions) '$t': _timeoutLabel(t),
        }),
      ],
    );
    if (r == null || !mounted) return;
    await lock.setTimeout(int.parse(r['t']!));
  }

  Future<void> _toggleEncryption(bool value) async {
    final ok = await confirmDialog(
      context,
      title: value ? 'Зашифровать базу данных?' : 'Снять шифрование?',
      message: value
          ? 'Данные на устройстве будут зашифрованы ключом из защищённого хранилища (Android Keystore). '
              'Если очистить данные приложения или перенести их на другой телефон без резервной копии, зашифрованные данные '
              'будет невозможно восстановить. Сначала сделайте экспорт копии. Операция займёт несколько секунд.'
          : 'Данные снова будут храниться на устройстве в обычном виде. Операция займёт несколько секунд.',
      confirmLabel: value ? 'Зашифровать' : 'Снять шифрование',
      danger: !value,
    );
    if (!ok || !mounted) return;
    final res = await runWithProgress(context, value ? 'Шифрование данных…' : 'Снятие шифрования…', () => security.setEncryption(value));
    if (!mounted) return;
    showToast(context, res.ok ? (value ? 'База данных зашифрована' : 'Шифрование снято') : (res.message ?? 'Не удалось изменить шифрование'));
  }

  Future<void> _resetStorage() async {
    final r = await showFormDialog(
      context,
      title: 'Сбросить хранилище',
      actionLabel: 'Удалить и начать заново',
      accent: AppColors.red,
      actionTextColor: Colors.white,
      fields: const [FieldSpec('w', 'Хранилище нельзя открыть. Будут удалены база данных и ключ — восстановить данные можно только из резервной копии. Введите СБРОС')],
      validate: (v) => v['w']!.trim().toUpperCase() == 'СБРОС',
    );
    if (r == null || !mounted) return;
    final res = await runWithProgress(context, 'Сброс хранилища…', security.resetStorage);
    if (!mounted) return;
    showToast(context, res.ok ? 'Хранилище создано заново' : (res.message ?? 'Не удалось сбросить хранилище'));
  }

  // ---------------- построение ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        backgroundColor: AppColors.panel,
        elevation: 0,
      ),
      body: ListenableBuilder(listenable: Listenable.merge([c, security, lock, if (security.backup != null) security.backup!, if (security.reminders != null) security.reminders!]), builder: (context, _) => _content()),
    );
  }

  Widget _content() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (c.loadFailed && security.encryptionSupported)
          _section('ХРАНИЛИЩЕ НЕДОСТУПНО', [
            _tile(Icons.error_outline, 'Сбросить хранилище', 'Если ключ утерян или база повреждена: удалить базу и начать заново', danger: true, onTap: _resetStorage),
          ]),
        _section('ПРОФИЛЬ', [
          _tile(Icons.person, 'Имя', c.userName.isEmpty ? 'не задано' : c.userName, onTap: _editName),
          _tile(Icons.currency_exchange, 'Валюта', '${currentCurrency.symbol} — ${currentCurrency.name} (только обозначение)', onTap: _editCurrency),
        ]),
        _section('ЦЕЛИ НА ДЕНЬ', [
          _tile(Icons.directions_walk, 'Шаги', fmtMoney(c.stepsGoal), onTap: _editStepsGoal),
          _tile(Icons.restaurant, 'Белок, г', '${c.proteinGoal}', onTap: _editProteinGoal),
        ]),
        _section('ЗДОРОВЬЕ', [
          if (!c.healthSupported)
            _tile(Icons.monitor_heart, 'Health Connect', 'Доступен на Android. Сейчас — ручной ввод.')
          else ...[
            _tile(
              Icons.monitor_heart,
              'Health Connect',
              healthStatusLine(c),
              trailing: c.healthSyncing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                  : Text(c.healthEnabled ? 'Синхр.' : 'Подключить', style: const TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.bold)),
              onTap: c.healthSyncing ? null : () => syncHealthWithToast(context, c),
            ),
            if (c.healthEnabled) _tile(Icons.link_off, 'Отключить синхронизацию', 'Разрешение в системе останется', onTap: c.disconnectHealth),
          ],
        ]),
        _section('БЕЗОПАСНОСТЬ', [
          _switchTile(
            Icons.lock,
            'Блокировка приложения',
            lock.enabled ? 'Биометрия или PIN устройства при запуске и возврате' : 'Запрашивать биометрию или PIN при открытии',
            lock.enabled,
            _toggleLock,
          ),
          if (lock.enabled) _tile(Icons.timer, 'Блокировать', _timeoutLabel(lock.timeoutSec), onTap: _pickTimeout),
          if (lock.enabled) _tile(Icons.lock_clock, 'Заблокировать сейчас', 'Закрыть приложение до подтверждения личности', onTap: lock.lockNow),
          _switchTile(
            Icons.visibility_off,
            'Скрывать содержимое',
            'В списке недавних приложений; на Android — и на скриншотах',
            lock.screenProtection,
            lock.setScreenProtection,
          ),
          if (security.encryptionSupported)
            _switchTile(
              Icons.enhanced_encryption,
              'Шифровать базу данных',
              security.encrypted ? 'Включено: данные на устройстве зашифрованы' : 'Выключено: данные хранятся в обычном виде',
              security.encrypted,
              security.busy ? null : _toggleEncryption,
            ),
        ]),
        _section('РАЗДЕЛЫ', [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Скройте то, чем не пользуетесь. Данные не удаляются: они остаются в Хронике, экспорте и копии.',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
          for (final s in Sections.all)
            adaptiveSwitchTile(
              context,
              key: ValueKey('section_${s.id}'),
              value: c.isShown(s.id),
              onChanged: (v) => c.setSectionShown(s.id, v),
              title: Text(s.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(s.where, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ),
        ]),
        _section('ОТКРЫТЫЙ ЭКСПОРТ', [
          // читается без LIFE OS: Excel, LibreOffice, любой текстовый редактор; это не резервная копия
          _tile(Icons.article_outlined, 'Хроника (Markdown)', 'Текст: месяцы, дни, события и заметки', onTap: () => _copyExport('Хроника', c.exportChronicleMarkdown())),
          for (final e in const {
            'events': ('События (CSV)', 'Все версии и отменённые — с пометками'),
            'checkins': ('Отметки дня (CSV)', 'Оценка, метки, заметка; все версии'),
            'transactions': ('Операции (CSV)', 'Доходы и расходы'),
            'days': ('Дни (CSV)', 'Шаги, сон, белок, капитал по дням'),
            'weights': ('Вес (CSV)', 'Замеры с источником'),
            'sets': ('Подходы (CSV)', 'Журнал тренировок с расчётным 1RM'),
          }.entries)
            _tile(Icons.table_chart_outlined, e.value.$1, e.value.$2, onTap: () => _copyExport(e.value.$1, c.exportCsv(e.key)!)),
        ]),
        if (security.reminders != null && security.reminders!.supported) _section('НАПОМИНАНИЯ', _reminderTiles(security.reminders!)),
        _section('РЕЗЕРВНАЯ КОПИЯ', _backupTiles(security.backup)),
        _section('ДАННЫЕ', [
          _tile(Icons.file_download_outlined, 'Импорт выписки банка (CSV)', 'Операции из выписки — в журнал, без повторов; импорт можно отменить',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatementImportScreen(controller: c)))),
          _tile(Icons.upload_file, 'Копия в буфер обмена', 'Разово: с шифрованием паролем или без', onTap: () => exportBackup(context, c, cipher: security.backupCipher)),
          _tile(Icons.download, 'Копия из буфера обмена', 'Обычная или зашифрованная; заменяет все данные', onTap: () => importBackupDialog(context, c, cipher: security.backupCipher)),
          _tile(Icons.auto_awesome, 'Загрузить примеры данных', 'Заменяет журнал, операции, цели и граф', onTap: _loadDemo),
          _tile(Icons.delete_forever, 'Сбросить все данные', 'Начать с чистого листа', danger: true, onTap: _reset),
        ]),
        _section('О ПРИЛОЖЕНИИ', [
          _tile(Icons.info_outline, 'Версия', appVersionLabel()),
          _tile(Icons.waving_hand, 'Пройти знакомство заново', 'Имя, цели, деньги — данные не удаляются', onTap: _restartOnboarding),
          _tile(Icons.storage, 'Формат данных', 'JSON v$kSchemaVersion • хранилище SQLite'),
          _tile(Icons.bug_report, 'Журнал диагностики', 'Записей: ${AppLog.recent.length} • нажмите, чтобы скопировать', onTap: _copyLog),
        ]),
      ],
    );
  }

  Widget _section(String title, List<Widget> tiles) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          ),
          Material(
            color: AppColors.card,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.small),
              side: const BorderSide(color: Colors.white10),
            ),
            child: Column(
              children: [
                for (int i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: Colors.white10, indent: 16, endIndent: 16),
                  tiles[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchTile(IconData icon, String title, String subtitle, bool value, ValueChanged<bool>? onChanged) {
    return adaptiveSwitchTile(
      context,
      // значок — украшение: при крупном шрифте его место нужнее тексту
      secondary: largeText(context) ? null : Icon(icon, color: AppColors.muted, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      value: value,
      activeThumbColor: AppColors.accent,
      onChanged: onChanged,
    );
  }

  Widget _tile(IconData icon, String title, String subtitle, {VoidCallback? onTap, Widget? trailing, bool danger = false}) {
    final color = danger ? AppColors.red : Colors.white;
    return ListTile(
      leading: largeText(context) ? null : Icon(icon, color: danger ? AppColors.red : AppColors.muted, size: 20),
      title: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right, color: Colors.white24) : null),
      onTap: onTap,
    );
  }
}
