import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../state/app_controller.dart';
import '../widgets/health_actions.dart';

/// Знакомство: имя, цели дня, деньги (по желанию), подключения и способ старта.
/// Показывается при первом запуске и по кнопке в настройках; данные пользователя не удаляет.
class OnboardingScreen extends StatefulWidget {
  final AppController controller;
  const OnboardingScreen({super.key, required this.controller});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pages = 4;

  AppController get c => widget.controller;

  final PageController _pageCtrl = PageController();
  int _page = 0;
  bool _demo = false;

  late final TextEditingController _name = TextEditingController(text: c.userName);
  late final TextEditingController _steps = TextEditingController(text: '${c.stepsGoal}');
  late final TextEditingController _protein = TextEditingController(text: '${c.proteinGoal}');
  late final TextEditingController _worth = TextEditingController(text: c.netWorth == 0 ? '' : '${c.netWorth}');
  late final TextEditingController _income = TextEditingController(text: c.monthlyIncome == 0 ? '' : '${c.monthlyIncome}');
  late final TextEditingController _expense = TextEditingController(text: c.monthlyExpense == 0 ? '' : '${c.monthlyExpense}');

  @override
  void dispose() {
    _pageCtrl.dispose();
    for (final t in [_name, _steps, _protein, _worth, _income, _expense]) {
      t.dispose();
    }
    super.dispose();
  }

  void _go(int page) {
    _pageCtrl.animateToPage(page, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _next() => _page < _pages - 1 ? _go(_page + 1) : _finish();

  void _skip() => c.completeOnboarding(userName: _name.text);

  void _finish() {
    c.completeOnboarding(
      userName: _name.text,
      stepsGoal: parseInt(_steps.text),
      proteinGoal: parseInt(_protein.text),
      netWorth: parseInt(_worth.text),
      income: parseInt(_income.text),
      expense: parseInt(_expense.text),
      demo: _demo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _skip, child: const Text('Пропустить', style: TextStyle(color: Colors.white38, fontSize: 12))),
            ),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _page = i),
                children: [_welcome(), _goals(), _money(), _startPage()],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: _page > 0 ? TextButton(onPressed: () => _go(_page - 1), child: const Text('Назад', style: TextStyle(color: Colors.white54))) : null,
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < _pages; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _page ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(color: i == _page ? AppColors.green : Colors.white24, borderRadius: BorderRadius.circular(3)),
                          ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, minimumSize: const Size(96, 40)),
                    onPressed: _next,
                    child: Text(last ? 'Начать' : 'Далее', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- страницы ----------------

  Widget _shell(IconData icon, String title, String subtitle, List<Widget> children) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: AppColors.green, size: 28),
          ),
          const SizedBox(height: 18),
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4)),
          const SizedBox(height: 22),
          ...children,
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {bool numeric = false, int? maxLength}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        maxLength: maxLength,
        keyboardType: numeric ? const TextInputType.numberWithOptions(signed: true) : TextInputType.text,
        decoration: InputDecoration(labelText: label, counterText: ''),
      ),
    );
  }

  Widget _welcome() => _shell(
        Icons.auto_awesome,
        'Добро пожаловать в Life OS',
        'Одно место для тела, денег, целей и связей между ними. Все данные хранятся на вашем устройстве. '
            'Знакомство займёт минуту — всё можно изменить позже в настройках.',
        [_field(_name, 'Как к вам обращаться?', maxLength: 40)],
      );

  Widget _goals() => _shell(
        Icons.flag,
        'Цели на день',
        'Они показываются на главном экране рядом с шагами и белком.',
        [
          _field(_steps, 'Шагов в день', numeric: true),
          _field(_protein, 'Белка в день, г', numeric: true),
        ],
      );

  Widget _money() => _shell(
        Icons.account_balance_wallet,
        'Деньги (по желанию)',
        'Стартовые цифры для вкладки «Капитал». Можно пропустить и заполнить позже — суммы нигде не отправляются.',
        [
          _field(_worth, 'Чистый капитал, ₽', numeric: true),
          _field(_income, 'Доход в месяц, ₽', numeric: true),
          _field(_expense, 'Расходы в месяц, ₽', numeric: true),
        ],
      );

  Widget _startPage() => _shell(
        Icons.rocket_launch,
        'Почти готово',
        'Подключите Health Connect, чтобы шаги и калории подтягивались сами, и выберите, с чего начать.',
        [
          if (c.healthSupported) ...[
            OutlinedButton.icon(
              onPressed: c.healthSyncing ? null : () => syncHealthWithToast(context, c),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.green, side: const BorderSide(color: AppColors.green), minimumSize: const Size(double.infinity, 44)),
              icon: Icon(c.healthEnabled ? Icons.check_circle : Icons.monitor_heart, size: 18),
              label: Text(c.healthEnabled ? 'Health Connect подключён' : 'Подключить Health Connect'),
            ),
            const SizedBox(height: 6),
            Text(healthStatusLine(c), style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ] else
            const Text('Health Connect доступен на Android — подключить можно позже в настройках.', style: TextStyle(color: Colors.white38, fontSize: 12)),
          if (c.isBlank) ...[
            const SizedBox(height: 22),
            const Text('С ЧЕГО НАЧАТЬ', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text('Чистый старт'), selected: !_demo, selectedColor: AppColors.green.withValues(alpha: 0.3), onSelected: (_) => setState(() => _demo = false)),
                ChoiceChip(label: const Text('Примеры данных'), selected: _demo, selectedColor: AppColors.green.withValues(alpha: 0.3), onSelected: (_) => setState(() => _demo = true)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _demo ? 'Заполним журнал, цели, граф и операции примерами — удобно, чтобы осмотреться. Удалить их можно в настройках.' : 'Всё начнётся с нуля — вы заполните только то, что нужно.',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      );
}
