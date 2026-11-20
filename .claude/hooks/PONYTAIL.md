# ponytail — встроен в проект

Плагин Claude Code [ponytail](https://github.com/DietrichGebert/ponytail) (MIT, лицензия — `PONYTAIL-LICENSE`),
версия из коммита `96608e0`. Облачные сессии не ставят плагины из сторонних каталогов, поэтому он встроен
как настройки проекта и работает везде, где открыт репозиторий:

- `.claude/hooks/ponytail-*.js` — хуки (подключены в `.claude/settings.json`): на старте сессии и субагента
  добавляют правила ponytail в контекст, на каждом сообщении отслеживают `/ponytail lite|full|ultra|off`;
- `.claude/skills/ponytail*/SKILL.md` — навыки и команды `/ponytail`, `/ponytail-review`, `/ponytail-audit` и др.

Не встроено: строка состояния и «доска» задач (модуль band) — в облачной сессии их нет.
Нужен `node` в PATH. Обновить — заменить эти файлы из репозитория автора и поправить коммит выше.
Правила проекта из `CLAUDE.md` главнее.
