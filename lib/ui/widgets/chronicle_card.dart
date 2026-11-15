import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../state/app_controller.dart';
import '../screens/chronicle_screen.dart';

/// Карточка HUB: последние записи хроники. Нажатие открывает всю хронику.
class ChronicleCard extends StatelessWidget {
  final AppController controller;
  const ChronicleCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final all = controller.chronicle;
    final latest = all.take(3).toList();
    return InkWell(
      key: const ValueKey('open_chronicle'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChronicleScreen(controller: controller))),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('ХРОНИКА', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                ),
                Text('записей ${all.length}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
              ],
            ),
            const SizedBox(height: 6),
            if (latest.isEmpty)
              const Text('Здесь будет лента вашего пути: события, процессы, достижения.', style: TextStyle(color: Colors.white38, fontSize: 12)),
            for (final e in latest)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        e.monthOnly ? monthYear(e.at).split(' ').first.substring(0, 3) : '${e.at.day}.${e.at.month.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                    Expanded(child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
