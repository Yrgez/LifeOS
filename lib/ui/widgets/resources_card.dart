import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/life_event.dart';
import '../../state/app_controller.dart';
import '../screens/resources_screen.dart';
import 'event_dialog.dart';
import 'process_ui.dart';

/// Карточка HUB: куда за 7 дней ушли ресурсы. Нажатие открывает экран «Ресурсы».
class ResourcesCard extends StatelessWidget {
  final AppController controller;
  const ResourcesCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final b = controller.resourceBreakdownFor(7);
    final t = b.total;
    return InkWell(
      key: const ValueKey('open_resources'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResourcesScreen(controller: controller))),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('РЕСУРСЫ ЗА 7 ДНЕЙ', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                ),
                Text('событий ${t.events}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
              ],
            ),
            const SizedBox(height: 6),
            if (t.events == 0)
              const Text('Отмечайте в событиях время, деньги и энергию — здесь будет видно, куда они уходят.',
                  style: TextStyle(color: Colors.white38, fontSize: 12))
            else ...[
              for (final line in resourceLines(t).take(2)) Text(line, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 2,
                children: [
                  for (final d in LifeDimension.all)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: dimensionChartColor(d), borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 4),
                        Text(
                          '${LifeDimension.labels[d]} ${b.byDimension[d]!.minutesKnown > 0 ? fmtMinutes(b.byDimension[d]!.minutes) : '· ${b.byDimension[d]!.events}'}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
