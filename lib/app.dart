import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'security/security_service.dart';
import 'state/app_controller.dart';
import 'ui/app_shell.dart';
import 'ui/widgets/lock_layer.dart';

class LifeOSApp extends StatelessWidget {
  final AppController controller;
  final SecurityService security;

  LifeOSApp({super.key, required this.controller, SecurityService? security}) : security = security ?? SecurityService.disabled();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LIFE OS',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // русский — и для системных текстов: календари, «Назад», «Показать меню»; их же читает TalkBack
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // слой блокировки — над всем приложением, включая открытые экраны и диалоги
      builder: (context, child) => LockLayer(lock: security.lock, child: child ?? const SizedBox()),
      home: MainNavigationScreen(controller: controller, security: security),
    );
  }
}
