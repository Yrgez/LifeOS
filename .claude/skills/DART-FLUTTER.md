# Dart and Flutter — встроен в проект

Официальный плагин Claude Code [Dart and Flutter](https://github.com/flutter/agent-plugins) (BSD-3,
лицензия — `DART-FLUTTER-LICENSE`), версия из коммита `ff6d472`. Облачные сессии не ставят плагины из
сторонних каталогов, поэтому он встроен как настройки проекта:

- `.claude/skills/dart-*`, `.claude/skills/flutter-*` — 25 навыков (анализ, тесты, вёрстка, пакеты, покрытие…);
- `.mcp.json` — Dart MCP server (`dart mcp-server`), включён в `.claude/settings.json`. Нужен Dart/Flutter в PATH:
  без него сервер не стартует, навыки работают.

Обновить — заменить эти папки из репозитория авторов и поправить коммит выше. Правила проекта из `CLAUDE.md` главнее
(архитектура — `AppController`/`ChangeNotifier`, не BLoC/Riverpod; ширина строки 160).
