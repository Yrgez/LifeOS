# Подключение Health Connect (Android)

Приложение читает **шаги** и **активные калории** из Health Connect. Samsung Health, часы и другие
приложения записывают данные туда же (в Samsung Health включите обмен с Health Connect в его настройках).
Белок из источника не читается — остаётся ручным вводом.

> Весь платформенный код — в `lib/data/health_connect_source.dart` (плагин `health: ^12.0.0`).
> Остальное приложение зависит только от интерфейса `HealthDataSource`.
> Шаги ниже собраны по README плагина и документации Health Connect; сверьте их с README
> установленной версии плагина — требования Android меняются между релизами.

## 1. `android/app/build.gradle(.kts)`
- `minSdk` — не ниже **26** (Android 8.0).
- `compileSdk` — актуальный (34+).

## 2. `MainActivity` — наследник `FlutterFragmentActivity`
```kotlin
package com.example.life_os

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

## 3. `android/app/src/main/AndroidManifest.xml`
Разрешения (внутри `<manifest>`):
```xml
<uses-permission android:name="android.permission.health.READ_STEPS"/>
<uses-permission android:name="android.permission.health.READ_ACTIVE_CALORIES_BURNED"/>
```
Проверка наличия Health Connect (внутри `<manifest>`):
```xml
<queries>
    <package android:name="com.google.android.apps.healthdata" />
</queries>
```
Экран с пояснением разрешений (внутри `<activity android:name=".MainActivity" ...>`):
```xml
<intent-filter>
    <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
</intent-filter>
```
Для Android 14+ (просмотр использования разрешений) рядом с `<activity>`:
```xml
<activity-alias
    android:name="ViewPermissionUsageActivity"
    android:exported="true"
    android:targetActivity=".MainActivity"
    android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
    <intent-filter>
        <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />
        <category android:name="android.intent.category.HEALTH_PERMISSIONS" />
    </intent-filter>
</activity-alias>
```

## 4. Проверка
1. `flutter pub get`, запуск на **реальном устройстве** (на эмуляторе нужен установленный Health Connect).
2. HUB → карточка Health & Activity → ⟳ → системный запрос разрешений → «Разрешить».
3. Если данных нет, откройте Health Connect → «Данные и доступ» и убедитесь, что Samsung Health/другое
   приложение записывает шаги.

## Что делает синхронизация
- Читает последние 7 дней: шаги (агрегат платформы, без двойного учёта источников) и активные калории
  (с удалением дублей).
- Обновляет «сегодня» и недельные графики. Если источник не вернул значение за день — старое не затирается.
- Автосинхронизация при запуске и возврате в приложение, не чаще раза в 2 минуты. «Отключить» выключает её
  (разрешение в системе остаётся — отозвать его можно в Health Connect).
- iOS (HealthKit) сознательно не подключён: чтение разрешений там скрыто системой и требует отдельной логики.
