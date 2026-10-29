import 'package:flutter/material.dart';

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
      title: 'Life OS Ultimate Engine',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // слой блокировки — над всем приложением, включая открытые экраны и диалоги
      builder: (context, child) => LockLayer(lock: security.lock, child: child ?? const SizedBox()),
      home: MainNavigationScreen(controller: controller, security: security),
    );
  }
}
