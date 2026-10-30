import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_log.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/app_data.dart';
import '../../security/app_lock.dart';
import '../../security/biometric_authenticator.dart';
import '../../security/security_service.dart';
import '../../security/security_settings.dart';
import '../../state/app_controller.dart';
import '../widgets/backup_actions.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';
import '../widgets/health_actions.dart';
import '../widgets/progress_dialog.dart';
import '../widgets/toast.dart';

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
        title: const Text('НАСТРОЙКИ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
        backgroundColor: AppColors.panel,
        elevation: 0,
      ),
      body: ListenableBuilder(listenable: Listenable.merge([c, security, lock]), builder: (context, _) => _content()),
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
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.green))
                  : Text(c.healthEnabled ? 'Синхр.' : 'Подключить', style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.bold)),
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
        _section('ДАННЫЕ', [
          _tile(Icons.upload_file, 'Экспорт резервной копии', 'В буфер обмена: с шифрованием паролем или без', onTap: () => exportBackup(context, c, cipher: security.backupCipher)),
          _tile(Icons.download, 'Импорт резервной копии', 'Обычная или зашифрованная; заменяет все данные', onTap: () => importBackupDialog(context, c, cipher: security.backupCipher)),
          _tile(Icons.auto_awesome, 'Загрузить примеры данных', 'Заменяет журнал, операции, цели и граф', onTap: _loadDemo),
          _tile(Icons.delete_forever, 'Сбросить все данные', 'Начать с чистого листа', danger: true, onTap: _reset),
        ]),
        _section('О ПРИЛОЖЕНИИ', [
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
            child: Text(title, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          ),
          Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
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
    return SwitchListTile(
      secondary: Icon(icon, color: Colors.white54, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      value: value,
      activeThumbColor: AppColors.green,
      onChanged: onChanged,
    );
  }

  Widget _tile(IconData icon, String title, String subtitle, {VoidCallback? onTap, Widget? trailing, bool danger = false}) {
    final color = danger ? AppColors.red : Colors.white;
    return ListTile(
      leading: Icon(icon, color: danger ? AppColors.red : Colors.white54, size: 20),
      title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right, color: Colors.white24) : null),
      onTap: onTap,
    );
  }
}
