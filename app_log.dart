import 'package:flutter/foundation.dart';

/// Минимальный логгер. Раньше ошибки глотались через `catch (_) {}`.
/// Точка расширения: [onError] — сюда позже подключается Crashlytics/Sentry.
class AppLog {
  static void Function(String message, Object? error, StackTrace? stack)? onError;
  static final List<String> _buffer = [];

  /// Последние записи (для экрана диагностики / отправки в поддержку).
  static List<String> get recent => List.unmodifiable(_buffer);

  static void clear() => _buffer.clear();

  /// Информационная запись (замеры, миграции): попадает в диагностический журнал, но не в [onError].
  static void d(String message) {
    final line = '${DateTime.now().toIso8601String()} $message';
    _buffer.add(line);
    if (_buffer.length > 100) _buffer.removeAt(0);
    debugPrint(line);
  }

  static void e(String message, [Object? error, StackTrace? stack]) {
    final line = '${DateTime.now().toIso8601String()} $message${error != null ? ': $error' : ''}';
    _buffer.add(line);
    if (_buffer.length > 100) _buffer.removeAt(0);
    debugPrint(line);
    if (stack != null) debugPrint('$stack');
    onError?.call(message, error, stack);
  }
}
