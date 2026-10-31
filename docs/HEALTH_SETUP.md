# Подключение Health Connect (Android)

Приложение читает из Health Connect **шаги**, **активные калории** и **белок** (из записей питания).
Samsung Health, часы и другие приложения записывают данные туда же (в Samsung Health включите обмен
с Health Connect в его настройках, в том числе запись питания).

> Весь платформенный код — в `lib/data/health_connect_source.dart` (плагин `health: ^12.0.0`).
> Остальное приложение зависит только от интерфейса `HealthDataSource`.
> Шаги ниже собраны по README плагина и документации Health Connect; сверьте их с README
> установленной версии плагина — требования Android меняются между релизами.

## Как это делается в CI
Папка `android/` в репозитории не хранится. Шаги сборки APK в `.github/workflows/ci.yml` создают её
(`flutter create`) и применяют настройки из разделов 1–3 автоматически. Вручную их нужно делать только
при локальной сборке с папкой `android/`.

## 1. `android/app/build.gradle(.kts)`
- `minSdk` — не ниже **26** (Android 8.0).
- `compileSdk` — **35 или выше** (требует библиотека Health Connect; в CI ставится 36 для всех плагинов).

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
<uses-permission android:name="android.permission.health.READ_NUTRITION"/>
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
1. Установите приложение **Health Connect** из Google Play, если его нет (на Android 13 и ниже оно не встроено;
   встроено с Android 14). Запускайте на **реальном устройстве**.
2. HUB → карточка Health & Activity → ⟳ → системные запросы разрешений → «Разрешить».
   Запросов два: шаги и калории, затем питание (белок). Отказ в питании не мешает шагам и калориям.
3. Если данных нет, откройте Health Connect → «Доступ приложений» и убедитесь, что Samsung Health/другое
   приложение записывает данные, а LifeOS имеет доступ к шагам, калориям и питанию.
4. Если подключали раньше (до появления белка), нажмите «Отключить» и подключите снова, чтобы выдать доступ к питанию.

## Что делает синхронизация
- Читает последние 7 дней: шаги (агрегат платформы, без двойного учёта источников) и активные калории
  (с удалением дублей).
- Белок: суммируется по записям питания за сегодня. Если значение больше нуля, оно заменяет введённый вручную
  белок за сегодня; нулевое или отсутствующее ручной ввод не трогает. Истории белка нет.
- Обновляет «сегодня» и недельные графики. Если источник не вернул значение за день — старое не затирается.
- Автосинхронизация при запуске и возврате в приложение, не чаще раза в 2 минуты. «Отключить» выключает её
  (разрешение в системе остаётся — отозвать его можно в Health Connect).
- iOS (HealthKit) сознательно не подключён: чтение разрешений там скрыто системой и требует отдельной логики.
