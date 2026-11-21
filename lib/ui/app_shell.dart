import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../security/security_service.dart';
import '../state/app_controller.dart';
import 'screens/chronicle_screen.dart';
import 'screens/gym_screen.dart';
import 'screens/hub_screen.dart';
import 'screens/mind_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/wealth_screen.dart';
import 'widgets/body_map_card.dart';

/// Оболочка приложения: навигация, предупреждение о хранилище, жизненный цикл.
/// Экраны лежат в `screens/`, переиспользуемые блоки — в `widgets/`.
class MainNavigationScreen extends StatefulWidget {
  final AppController controller;
  final SecurityService security;
  MainNavigationScreen({super.key, required this.controller, SecurityService? security}) : security = security ?? SecurityService.disabled();

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> with WidgetsBindingObserver {
  AppController get c => widget.controller;

  int _currentIndex = 0;
  final BodyMapSelection _selection = BodyMapSelection(); // выбор на карте тела переживает переключение вкладок
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // «восстановление» мышц зависит от времени — раз в минуту просим перерисовку
    _tickTimer = Timer.periodic(const Duration(minutes: 1), (_) => c.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    _selection.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      c.onResume();
      unawaited(widget.security.backup?.maybeRun());
      unawaited(widget.security.reminders?.resync());
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      c.flush();
      // уход из приложения: расписание по свежим данным (день отмечен — вечером не спросим)
      if (state == AppLifecycleState.paused) unawaited(widget.security.reminders?.resync());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      // знакомство — только когда данные прочитаны (иначе при сбое хранилища пользователь прошёл бы его впустую)
      builder: (context, _) => (c.loaded && !c.onboardingDone) ? OnboardingScreen(controller: c) : _buildScaffold(),
    );
  }

  Widget _storageBanner() {
    return Container(
      width: double.infinity,
      color: AppColors.red.withValues(alpha: 0.18),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: const Text(
        'Хранилище недоступно или данные от более новой версии — изменения не сохраняются.',
        style: TextStyle(fontSize: 11, color: AppColors.text),
      ),
    );
  }

  Widget _screen() {
    switch (_currentIndex) {
      case 0:
        return HubScreen(controller: c, security: widget.security);
      case 1:
        return GymScreen(controller: c, selection: _selection);
      case 2:
        return MindScreen(controller: c);
      case 3:
        return WealthScreen(controller: c);
      default:
        return ChronicleScreen(controller: c, embedded: true);
    }
  }

  Widget _buildScaffold() {
    return Scaffold(
      // строится только активный экран (раньше строились все пять на каждый setState)
      body: SafeArea(
        child: Column(
          children: [
            if (c.loadFailed) _storageBanner(),
            Expanded(child: _screen()),
          ],
        ),
      ),
      bottomNavigationBar: _FloatingNav(current: _currentIndex, onSelect: (i) => setState(() => _currentIndex = i)),
    );
  }
}

/// Вкладки: PRESENT, три измерения жизни, PAST.
const _tabs = [
  (key: 'tab_today', label: 'Сегодня', icon: Icons.grid_view_rounded),
  (key: 'tab_body', label: 'Тело', icon: Icons.accessibility_new),
  (key: 'tab_mind', label: 'Разум', icon: Icons.hub_outlined),
  (key: 'tab_material', label: 'Материальное', icon: Icons.account_balance_wallet_outlined),
  (key: 'tab_chronicle', label: 'Хроника', icon: Icons.history),
];

/// Плавающая нижняя панель: скруглённая «таблетка» над фоном, активная вкладка — в круге.
/// Подписи — в подсказках и для экранного диктора (иконки без текста, как в макете).
class _FloatingNav extends StatelessWidget {
  final int current;
  final ValueChanged<int> onSelect;
  const _FloatingNav({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.raised,
            borderRadius: BorderRadius.circular(AppRadii.sheet),
            border: Border.all(color: const Color(0x1AFFFFFF)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Semantics(
                  selected: i == current,
                  child: Tooltip(
                    message: _tabs[i].label,
                    child: InkResponse(
                      key: ValueKey(_tabs[i].key),
                      onTap: () => onSelect(i),
                      radius: 28,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: i == current ? const Color(0xFF2C2C2E) : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_tabs[i].icon, size: 23, color: i == current ? AppColors.text : const Color(0xFF8E8E93), semanticLabel: _tabs[i].label),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
