import 'utils.dart';

/// Правила автоматической резервной копии. Чистая логика без Flutter.
///
/// Имя файла несёт время копии: «catenna-backup-2026-11-18-2031.catenna». По имени же отбираются только свои
/// файлы — чужие в папке не трогаются. Старые копии удаляются, только когда новая уже записана.

const backupFilePrefix = 'catenna-backup-';
const backupFileExtension = '.catenna';
final _nameRe = RegExp(r'^catenna-backup-(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(?:-\d+)?\.catenna$');

/// Варианты частоты автокопии, дней.
const backupIntervalOptions = [1, 7, 30];

/// Сколько последних копий хранить.
const backupKeepCount = 8;

/// Через сколько дней без копии показывать напоминание на «Сегодня».
const backupReminderDays = 14;

String backupFileName(DateTime t) =>
    '$backupFilePrefix${dayKey(t)}-${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}$backupFileExtension';

/// Время копии по имени файла; null — файл не наш.
DateTime? backupTimeOf(String name) {
  final m = _nameRe.firstMatch(name);
  if (m == null) return null;
  final p = [for (var i = 1; i <= 5; i++) int.parse(m[i]!)];
  return DateTime(p[0], p[1], p[2], p[3], p[4]);
}

/// Пора ли делать копию: копий не было или с последней прошло [intervalDays] календарных дней.
bool backupDue(DateTime? last, DateTime now, int intervalDays) {
  if (last == null) return true;
  final days = DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(last.year, last.month, last.day)).inDays;
  return days >= intervalDays;
}

/// Полных дней с последней копии; null — копий не было.
int? daysSinceBackup(DateTime? last, DateTime now) =>
    last == null ? null : DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(last.year, last.month, last.day)).inDays;

/// Какие из [names] удалить, чтобы осталось [keep] самых новых своих копий. Чужие файлы — никогда.
List<String> backupsToDelete(Iterable<String> names, {int keep = backupKeepCount}) {
  final ours = [for (final n in names) if (backupTimeOf(n) != null) n]..sort((a, b) => b.compareTo(a));
  return ours.length <= keep ? const [] : ours.sublist(keep);
}
