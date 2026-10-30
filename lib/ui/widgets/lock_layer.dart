import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../security/app_lock.dart';

/// Слой защиты поверх всего приложения (включая открытые экраны и диалоги):
/// экран блокировки, когда приложение заблокировано, и «шторка» вместо содержимого в списке приложений.
class LockLayer extends StatelessWidget {
  final AppLock lock;
  final Widget child;
  const LockLayer({super.key, required this.lock, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (lock.locked) LockScreen(lock: lock) else if (lock.shielded) const ShieldCover(),
        ],
      ),
    );
  }
}

/// Непрозрачная шторка: в миниатюре приложения в списке недавних видна только она.
class ShieldCover extends StatelessWidget {
  const ShieldCover({super.key});

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Color(0xFF090B0E),
      child: Center(child: Icon(Icons.lock_outline, size: 48, color: Colors.white24)),
    );
  }
}

/// Экран блокировки. При появлении сам запрашивает биометрию; если запрос отменён — остаётся кнопка.
class LockScreen extends StatefulWidget {
  final AppLock lock;
  const LockScreen({super.key, required this.lock});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.lock.unlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = widget.lock;
    return Material(
      color: const Color(0xFF090B0E),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.lock, color: AppColors.green, size: 36),
                ),
                const SizedBox(height: 20),
                const Text('Life OS заблокирован', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Подтвердите личность, чтобы продолжить', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 13)),
                if (lock.message != null) ...[
                  const SizedBox(height: 14),
                  Text(lock.message!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.amber, fontSize: 12)),
                ],
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, minimumSize: const Size(200, 46)),
                  onPressed: lock.authenticating ? null : lock.unlock,
                  icon: const Icon(Icons.fingerprint, color: Colors.black),
                  label: const Text('Разблокировать', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
