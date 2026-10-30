import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../security/security_service.dart';
import '../../state/app_controller.dart';
import '../widgets/body_map_card.dart';
import '../widgets/comparison_card.dart';
import '../widgets/health_card.dart';
import 'settings_screen.dart';

/// Вкладка HUB: готовность тела, здоровье, сравнение метрик, карта тела.
class HubScreen extends StatelessWidget {
  final AppController controller;
  final BodyMapSelection selection;
  final SecurityService security;
  const HubScreen({super.key, required this.controller, required this.selection, required this.security});

  AppController get c => controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('EXECUTIVE DASHBOARD', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    const SizedBox(height: 4),
                    Text(c.userName.isEmpty ? 'Life OS' : c.userName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite, color: AppColors.green, size: 14),
                    const SizedBox(width: 6),
                    Text('Готовность тела: ${c.systemReadiness}%', style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white54),
                tooltip: 'Настройки',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(controller: c, security: security))),
              ),
            ],
          ),
          const SizedBox(height: 12),
          HealthCard(controller: c),
          const SizedBox(height: 16),
          ComparisonCard(controller: c),
          const SizedBox(height: 16),
          BodyMapCard(controller: c, selection: selection),
        ],
      ),
    );
  }
}
