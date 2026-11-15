import '../models/models.dart';

/// Восстановление мышц без единого процента. Это ОЦЕНКА по типовому времени восстановления группы
/// (`recoveryHours`) и времени последней тренировки — не измерение. Поэтому показываем то, что
/// действительно известно: когда была тренировка и сколько часов осталось по типовой оценке.
class MuscleRecovery {
  final String id;
  final String name;
  final DateTime? lastTrainedAt;
  final double recoveryHours; // типовое время восстановления
  final int hoursLeft; // по оценке; 0 — восстановлена
  const MuscleRecovery({required this.id, required this.name, this.lastTrainedAt, required this.recoveryHours, required this.hoursLeft});

  bool get recovered => hoursLeft == 0;
}

class RecoveryOverview {
  final int total;
  final List<MuscleRecovery> recovering; // ещё восстанавливаются — сначала те, кому дольше
  const RecoveryOverview(this.total, this.recovering);

  int get recovered => total - recovering.length;
}

MuscleRecovery muscleRecovery(MuscleGroup m, DateTime now) {
  final t = m.lastTrainedAt;
  var left = 0;
  if (t != null && m.recoveryHours > 0) {
    final passed = now.difference(t).inMinutes / 60.0;
    if (passed < m.recoveryHours) left = (m.recoveryHours - passed).ceil();
  }
  return MuscleRecovery(id: m.id, name: m.name, lastTrainedAt: t, recoveryHours: m.recoveryHours, hoursLeft: left);
}

RecoveryOverview recoveryOverview(Map<String, MuscleGroup> muscles, DateTime now) {
  final recovering = [
    for (final m in muscles.values)
      if (!muscleRecovery(m, now).recovered) muscleRecovery(m, now),
  ]..sort((a, b) => b.hoursLeft.compareTo(a.hoursLeft));
  return RecoveryOverview(muscles.length, recovering);
}

/// «≈ 20 ч» / «≈ 2 дн» — округлённо, без ложной точности до минут.
String fmtHoursLeft(int h) => h < 24 ? '≈ $h ч' : '≈ ${(h / 24).round()} дн';
