---
name: new-screen
description: Чек-лист для нового экрана, диалога или блока интерфейса LIFE OS по правилам CLAUDE.md — данные через AppController, реестр Sections, дизайн, доступность, тесты крупного шрифта и узкого экрана. Использовать при добавлении или заметной переделке экрана в lib/ui/screens, диалога или переиспользуемого блока в lib/ui/widgets.
---

# Новый экран LIFE OS

Пройти по всем пунктам до PR. Пункт не подходит — явно сказать почему, а не пропускать молча.

## 1. Где что лежит
- [ ] Экран — `lib/ui/screens/<имя>_screen.dart`, конструктор принимает `AppController controller`.
- [ ] Переиспользуемый блок или диалог — `lib/ui/widgets/`.
- [ ] Логика без Flutter (подсчёты, фильтры, тексты из данных) — `lib/core/`, модели — `lib/models/`.
  Такую логику покрыть юнит-тестом в `test/` без виджетов.

## 2. Данные
- [ ] UI ничего не меняет напрямую — только методы `AppController` (`lib/state/app_controller.dart`).
- [ ] Новая доменная операция — расширение в `lib/state/ops/<область>_ops.dart` (`part of` контроллера), не метод класса.
- [ ] Любая мутация журнала (подходы, операции, события, дневные снимки) попадает в `_pending` (`ChangeSet`) —
  иначе упадёт `test/storage_sync_test.dart`.
- [ ] Правка = новая версия (`supersedesId`), отмена = `voidedAt`. Физическое удаление — только явным действием
  с подтверждением (`lib/ui/widgets/confirm_dialog.dart`).
- [ ] Изменился JSON → поднять `kSchemaVersion` (`lib/data/app_data.dart`). Изменились таблицы → `kDbVersion`
  и шаг в `onUpgradeSchema`; новая таблица — в `SqliteAppRepository.tables` (`lib/data/sqlite_app_repository.dart`).
- [ ] Плагин — только за интерфейсом (`AppRepository`, `HealthDataSource`, `FileSource`, `BackupStorage`,
  `ReminderScheduler` и т. п.).

## 3. Принципы продукта
- [ ] Только данные пользователя или источника — никаких выдуманных показателей.
- [ ] Нет единого «индекса жизни». Оценки названы оценками и округлены. Субъективные шкалы не усредняются.
- [ ] `null` («не указано») ≠ 0. Мало данных — так и писать: «указано в 2 из 5».
- [ ] Рядом с данными видно происхождение (`source`) и время записи (`recordedAt`), где это уместно.
- [ ] Информация и контекст, а не оценки и предписания.
- [ ] Ничего не уходит наружу. Разрешения INTERNET нет.

## 4. Видимость
- [ ] Необязательный блок — новый `AppSection` в `Sections.all` (`lib/core/sections.dart`) с понятным `where`,
  а показ — под `c.isShown(Sections.<id>)`. Ядро (измерения, события, процессы, цели, Хроника) не скрывается.

## 5. Дизайн
- [ ] Тексты и комментарии — на русском.
- [ ] Деньги — только `fmtCur` / `cur` (`lib/core/currency.dart`), без «₽» в строках.
- [ ] Плитки — `tileDecoration()` и `AppRadii`; текст — `AppColors.text` / `AppColors.muted`;
  главное действие — белое `AppColors.accent`. Цвет только со смыслом (измерения, доход/расход, предупреждения).
- [ ] Графики: заливки — `dimensionChartColor`, значения подписаны текстом.
- [ ] Минимум интерфейсного шума.

## 6. Доступность
- [ ] Нарисованный график — в `ChartSemantics` с описанием из `describeSeries` (`lib/core/chart_text.dart`);
  нажимаемое на холсте — узлами `semanticsBuilder`.
- [ ] У `IconButton` — `tooltip`. Область нажатия ≥ 48 px; переключатели режимов — `SegmentPill`.
- [ ] Цвет текста с контрастом ≥ 4.5:1 (фиолетовый — `AppColors.violetText`).
- [ ] Плитки в ряд — `AdaptivePair`; строка «текст — значение» — `LeadTrailing`; переключатель — `adaptiveSwitchTile`.

## 7. Тесты
- [ ] Экран — в карту `screens` в `test/large_text_test.dart` (`'Название': (c) => NewScreen(controller: c)`);
  диалог — в карту `dialogs` там же.
- [ ] Экран, куда ведёт навигация, — в карту `screens` в `test/accessibility_test.dart` с путём по ключам
  (`ValueKey('open_<имя>')` на кнопке входа).
- [ ] Новая вкладка — в проверку узкого экрана 360 px (`test/ui_smoke_test.dart`).
- [ ] Новый раздел `Sections` — проверить `test/sections_test.dart`.
- [ ] Новое разрешение или нативная настройка — в манифест/Gradle и в `test/android_project_test.dart`.

## 8. Проверка
```
flutter pub get && flutter analyze --no-fatal-infos && flutter test
```
Если Flutter в окружении нет — сказать об этом и положиться на CI (`.github/workflows/ci.yml`), не выдавая
непроверенное за проверенное. Внешний вид на Galaxy S10 — навык `trial-build`.
