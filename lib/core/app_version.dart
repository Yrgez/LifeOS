/// Версия сборки. Передаётся при сборке (`--dart-define`, см. `.github/workflows/ci.yml`):
/// версия — из `pubspec.yaml`, номер сборки — число коммитов (только растёт), коммит — откуда собрано.
/// У локального запуска без них — «сборка для разработки».
library;

const String kAppVersion = String.fromEnvironment('LIFEOS_VERSION');
const String kAppBuild = String.fromEnvironment('LIFEOS_BUILD');
const String kAppCommit = String.fromEnvironment('LIFEOS_COMMIT');

/// «1.1.0 (сборка 412) · 4b9e89e»; без данных сборки — «сборка для разработки».
String appVersionLabel({String version = kAppVersion, String build = kAppBuild, String commit = kAppCommit}) {
  if (version.isEmpty) return 'сборка для разработки';
  final c = commit.length > 7 ? commit.substring(0, 7) : commit;
  return [
    build.isEmpty ? version : '$version (сборка $build)',
    if (c.isNotEmpty) c,
  ].join(' · ');
}
