part of '../app_controller.dart';

/// Видимость разделов: человек скрывает то, что ему не нужно. Меняется только вид — данные остаются.
/// Расширение того же library: работает с состоянием контроллера напрямую, мутации — только через `_commit`.
extension SectionOps on AppController {
  bool isShown(String section) => !_d.hiddenSections.contains(section);

  Set<String> get hiddenSections => Set.unmodifiable(_d.hiddenSections);

  /// Показать или скрыть раздел. false — раздела нет в реестре.
  bool setSectionShown(String section, bool shown) {
    if (!Sections.isValid(section)) return false;
    if (isShown(section) == shown) return true;
    _commit(() => shown ? _d.hiddenSections.remove(section) : _d.hiddenSections.add(section));
    return true;
  }
}
