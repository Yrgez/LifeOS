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
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      c.flush();
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
        style: TextStyle(fontSize: 11, color: Colors.white70),
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
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white10, width: 1))),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: AppColors.panel,
          selectedItemColor: AppColors.green,
          unselectedItemColor: Colors.white38,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          items: const [
            // PRESENT, три измерения жизни, PAST
            BottomNavigationBarItem(icon: Icon(Icons.today_outlined), activeIcon: Icon(Icons.today), label: 'Сегодня'),
            BottomNavigationBarItem(icon: Icon(Icons.accessibility_new), label: 'Тело'),
            BottomNavigationBarItem(icon: Icon(Icons.psychology_outlined), activeIcon: Icon(Icons.psychology), label: 'Разум'),
            BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), activeIcon: Icon(Icons.account_balance_wallet), label: 'Материальное'),
            BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Хроника'),
          ],
        ),
      ),
    );
  }
}
