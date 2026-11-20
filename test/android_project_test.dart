import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/app_version.dart';

/// Настройки Android-проекта, от которых зависят обновление, приватность и безопасность (docs/RELEASE.md).
/// Сам APK проверяет CI (`aapt2 dump badging`, `apksigner verify`).
void main() {
  String read(String p) => File(p).readAsStringSync();

  test('идентификатор постоянный, minSdk для Health Connect, подпись из ключа, правила R8', () {
    final g = read('android/app/build.gradle.kts');
    expect(g, contains('applicationId = "io.github.yrgez.lifeos"'));
    expect(g, contains('namespace = "io.github.yrgez.lifeos"'));
    expect(g, contains('minSdk = 26'));
    expect(g, contains('LIFEOS_KEYSTORE_PATH'));
    expect(g, contains('"proguard-rules.pro"'));
    expect(read('android/app/proguard-rules.pro'), contains('-keep class net.sqlcipher.** { *; }'));
    expect(File('android/app/src/main/kotlin/io/github/yrgez/lifeos/MainActivity.kt').existsSync(), isTrue);
  });

  test('манифест: без сети, без системной копии базы, биометрия и Health Connect', () {
    final m = read('android/app/src/main/AndroidManifest.xml');
    expect(m, contains('android.permission.INTERNET" tools:node="remove"'));
    expect(m, contains('android:allowBackup="false"'));
    expect(m, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    expect(m, contains('android.permission.USE_BIOMETRIC'));
    for (final p in ['READ_STEPS', 'READ_ACTIVE_CALORIES_BURNED', 'READ_NUTRITION', 'READ_SLEEP', 'READ_WEIGHT']) {
      expect(m, contains('android.permission.health.$p'), reason: p);
    }
    expect(m, contains('androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE'));
    // Skia вместо Impeller: Impeller портит текст на Galaxy S10 (Mali-G76)
    expect(m, contains('android:name="io.flutter.embedding.android.EnableImpeller"\n            android:value="false"'));
    final rules = read('android/app/src/main/res/xml/data_extraction_rules.xml');
    expect('<exclude domain="database"'.allMatches(rules).length, 2); // и облако, и перенос на новый телефон
  });

  test('MainActivity: FlutterFragmentActivity и канал защиты экрана', () {
    final a = read('android/app/src/main/kotlin/io/github/yrgez/lifeos/MainActivity.kt');
    expect(a, contains('FlutterFragmentActivity()'));
    expect(a, contains('"life_os/screen_security"')); // как в lib/security/screen_security.dart
    expect(read('lib/security/screen_security.dart'), contains("'life_os/screen_security'"));
    expect(read('android/app/src/main/res/values/styles.xml'), contains('Theme.AppCompat'));
  });

  test('свой адаптивный значок: три измерения, тематический слой, без PNG Flutter', () {
    expect(read('android/app/src/main/AndroidManifest.xml'), contains('android:icon="@mipmap/ic_launcher"'));
    final icon = read('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml');
    for (final l in ['@drawable/ic_launcher_foreground', '@drawable/ic_launcher_monochrome']) {
      expect(icon, contains(l));
    }
    final fg = read('android/app/src/main/res/drawable/ic_launcher_foreground.xml');
    for (final c in ['#E2704F', '#7E9BFF', '#D8AE4A']) {
      expect(fg, contains(c)); // как AppColors.body / mind / material (dimensionColor)
    }
    expect(File('android/app/src/main/res/mipmap-hdpi/ic_launcher.png').existsSync(), isFalse);
  });

  test('CI собирает закреплённой версией Flutter (переключатель Impeller в новых версиях могут убрать)', () {
    for (final p in ['.github/workflows/ci.yml', '.github/workflows/release.yml']) {
      final w = read(p);
      expect('subosito/flutter-action'.allMatches(w).length, 'flutter-version: 3.50.0'.allMatches(w).length, reason: p);
    }
  });

  test('ключ подписи не попадает в репозиторий', () {
    final ignore = read('android/.gitignore');
    expect(ignore, contains('key.properties'));
    expect(ignore, contains('**/*.jks'));
  });

  test('версия сборки: из CI — версия, номер и коммит; локально — «сборка для разработки»', () {
    expect(appVersionLabel(version: '', build: '', commit: ''), 'сборка для разработки');
    expect(appVersionLabel(version: '1.1.0', build: '412', commit: '4b9e89e609cf368be66'), '1.1.0 (сборка 412) · 4b9e89e');
    expect(appVersionLabel(version: '1.1.0', build: '', commit: ''), '1.1.0');
  });
}
