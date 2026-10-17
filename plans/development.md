# План разработки Kaizen Protocol (v1)

## 1. Концепция и принципы v1

**Kaizen Protocol** — децентрализованный оркестратор конфигураций и зависимостей рабочего окружения на **Rust**. Каждый модуль (редактор, WM, шелл, пресет хоткеев) живёт в своём репозитории и общается с ядром по единому контракту.

Семь базовых правил первой версии (KISS):
1. **UI-агностичное ядро (`kaizen-core`):** ядро — это чистая Rust-библиотека (и опционально JSON-RPC сервер), которая ничего не знает про терминал, `stdin`/`stdout` или кнопки. CLI, TUI (`ratatui`) и GUI (`Tauri` / `Iced` / `GPUI`) — это тонкие клиенты поверх ядра. Ядро возвращает клиенту структурированный `Plan` (диффы, список пакетов, конфликты), а клиент передаёт обратно решения пользователя.
2. **Stage 0 Bootstrap:** сам Kaizen собирается в единый статический бинарник и умеет с нуля поднимать первичные инструменты ОС (`git`, `brew`, `flatpak`, `mise`) до установки пакетов.
3. **Единый контекст (`context.json`) и Feature Propagation:** пользователь задаёт глобальные настройки (шрифты, тему, воркспейсы, раскладку, хоткеи) в `config.toml`. Kaizen валидирует их и раздаёт всем пакетам через `context.json`. Механизм **Feature Propagation** автоматически обогащает контекст списками активных пакетов (`context.packages`) и тегов (`context.tags`), позволяя пакетам динамически адаптировать конфигурации и интеграции.
4. **Никакого `chezmoi` в ядре:** пакеты отдают готовые файлы (статикой, через встроенный шаблонизатор или свой скрипт), а Kaizen сам раскладывает их в `$HOME`.
5. **1 целевой файл = 1 пакет-владелец + Авто-бэкапы:** два пакета не могут редактировать один и тот же файл (для общих точек входа используются `conf.d/` директории). Если в `~/.config` уже лежат старые файлы пользователя или файл был изменён вручную (`sha256` не совпал), срабатывает политика бэкапов (`[backup]`).
6. **Теги, `mutex` и Reference Counting зависимостей:**
   - каждый пакет обязан объявить `tags = [...]` для сквозного поиска фич и зависимостей, а также для распространения в `context.tags`;
   - пакеты, захватывающие монопольный ресурс ОС (например, оконные менеджеры), объявляют `mutex = "tiling"` — если среди активных пакетов оказывается два пакета с одинаковым `mutex`, Kaizen возвращает `AmbiguityError` (пакеты с одинаковым `mutex` взаимоисключающи);
   - системные пакеты (`brew`, `dnf`, `apt`, `flatpak`, `mise`) учитываются через множество владельцев (`required_by`) и удаляются, когда список владельцев пустеет.
7. **Принцип «Inline-First и фрактальный `extends`»:** любая секция (`[keyboard]`, `[ui]`, `[package.dependencies]`, `[[package]]`) может быть полностью описана инлайн в одном входном файле (`config.toml`, `package.toml`) или вынесена в отдельный локальный/удалённый модуль через `extends = { path = "...", type = "local" | "url" | "git" }`. Ядро применяет детерминированный `deep-merge` (локальные ключи переопределяют базовые, списки объединяются). Отдельные файлы (`keyboard.toml`, `dependencies.toml`, `preset.toml`) служат стандартными Lego-блоками экосистемы для публикации и шеринга.

---

## 2. Архитектура и контракты файлов

```text
config.toml (+ extends) ──┐
preset.toml             ──┼──► [ kaizen-core (Rust Headless Engine) ] ◄──► CLI / TUI / GUI
package.toml + schema   ──┘                     │
                                                ├──► Stage 0 Bootstrap (git, brew, flatpak, mise)
                                                ├──► ~/.config/kaizen/context.json
                                                ├──► Деплой в $HOME + Snapshots (state.json + backups/)
                                                └──► Пакетные менеджеры ОС (state.json: required_by)
```

### Концепция «1 входной файл + Lego-модули»
Пользователь может вести всю систему в одном компактном `config.toml`, не создавая лишних файлов. При разрастании настроек или желании поделиться своей раскладкой в сети любая секция выносится в отдельный файл/репозиторий и подключается через `extends`. Аналогично для пакетов: простые пакеты описывают свои зависимости инлайн в `package.toml`, а сложные могут выносить их в `dependencies.toml`.

### Основные файлы протокола (`docs/examples/*`)
* **`config.toml`** (`docs/examples/config.example.toml`) — корневой конфиг пользователя:
  * версия схемы (`schema-version = 1`);
  * глобальные секции: `[system]`, `[privacy]`, `[backup]`, `[ui]`, `[keyboard]`, `[env]`;
  * подключение пресетов (`[[resources]]`) или инлайн-пакетов (`[[package]]`);
  * поддержка `extends = { path = "...", type = "git" | "url" | "local" }` внутри любой секции.
* **`preset.toml`** (`docs/examples/preset.example.toml`) — сборка из нескольких пакетов (`[[package]]`), флаг активности `enabled` и передача аргументов (`[package.arguments]`).
* **`package.toml`** (`docs/examples/package.example.toml`) — манифест пакета:
  * версия схемы (`schema-version = 1`);
  * метаданные (`name`, `license`, `tags = [...]`);
  * требования к совместимости (`[package.compatibility]` с `kaizen = ">=1.0.0, <2.0.0"` и версиями ОС);
  * опциональный ключ взаимного исключения `mutex = "..."` (при конфликте двух активных пакетов с одним `mutex` выдаётся `AmbiguityError`);
  * путь к JSON-схеме аргументов (`schema = "./schema.example.json"`) и файлу зависимостей (`dependencies = "./dependencies.example.toml"` или инлайн `[package.dependencies]`);
  * декларативный маппинг файлов в `$HOME` (`[[package.files]]` со строковым или per-OS `target`) или `build-script`.
* **`dependencies.toml`** (`docs/examples/dependencies.example.toml`) — декларация системных пакетов, нужных модулю (`[macos.brew]`, `[fedora.dnf]`, `[fedora.flatpak]`, `[ubuntu.apt]`, `[mise]`).
* **`keyboard.toml`** (`docs/examples/keyboard.example.toml`) — семантическая карта хоткеев (`action_id = "keys"`) и оверлеи раскладок (`[layout.colemak.*]`).
* **`kaizen.lock`** — пиннинг точных git-коммитов (`rev`), хэшей контента (`sha256`) и статуса проверок `[privacy]`.
* **`state.json`** — локальное состояние системы (`files`, `dependencies.required_by`, `backups`).

---

## 3. Технологический стек (Rust Workspace)

* **Workspace:**
  * `crates/kaizen-core` — чистая библиотека: модели, парсинг, резолвер `extends`, проверка `mutex`, поиск по `tags`, валидация схем и версий, планировщик (`Plan` / `Conflict` / `Resolution`), бэкапы, адаптеры пакетных менеджеров.
  * `crates/kaizen-cli` — тонкий CLI-клиент поверх `kaizen-core`.
* **Ключевые крейты:**
  * `serde`, `serde_json`, `toml`, `toml_edit` — сериализация и глубокий мерж TOML/JSON.
  * `semver` — проверка диапазонов совместимости версий Kaizen и ОС.
  * `jsonschema` — валидация аргументов пакетов по их `schema.json`.
  * `sha2` — подсчёт `sha256` для контроля целостности и ручных правок.
  * `similar` — расчёт текстовых диффов для `--dry-run` и разрешения конфликтов.
  * `clap` — интерфейс командной строки.

---

## 4. Пошаговый план реализации (Step-by-Step)

### Шаг 1. Финализация спецификации и JSON Schema
- Привести примеры в `docs/*.example.*` к актуальному контракту v1 с `schema-version = 1`.
- Написать JSON Schema (`config.schema.json`, `package.schema.json`, `dependencies.schema.json`, `preset.schema.json`) для валидации и автодополнения через Taplo LSP.

### Шаг 2. Каркас `kaizen-core` и Stage 0 Bootstrap
- Инициализировать Cargo workspace (`kaizen-core`, `kaizen-cli`).
- Реализовать **Stage 0 Bootstrap** для чистой ОС:
  - детектор платформы (`macos`, `fedora`, `ubuntu`);
  - проверка и автоматическая установка первичных инструментов:
    - **macOS:** Xcode CLI tools, `git`, `brew`, `mise`;
    - **Fedora:** `git`, `flatpak` (+ Flathub), `mise`;
    - **Ubuntu/Debian:** `git`, `flatpak`, `mise`.

### Шаг 3. Загрузчик конфига, фрактальный `extends`, версионирование схемы и `mutex`
- Реализовать парсер `config.toml` и подключённых `preset.toml`.
- **Универсальный фрактальный резолвер `extends`:**
  - поддержать `extends` для любых секций манифестов (`config.toml`, `package.toml`, `preset.toml`) с рекурсивным `deep-merge` (приоритет: локальные ключи > базовые ключи из `extends`, списки объединяются с дедупликацией по идентификатору);
- **Проверка версии схемы и совместимости ядра:**
  - валидация `schema-version`: если манифест использует версию схемы выше, чем поддерживается установленным ядром, возвращать `UnsupportedSchemaVersionError` с требованием обновить Kaizen;
  - валидация `[package.compatibility.kaizen]`: если текущая версия `kaizen-core` не удовлетворяет SemVer-диапазону пакета, возвращать `IncompatibleEngineError`.
- Поддержать `enabled` в декларациях пакетов: по умолчанию `true`; `false` сохраняет декларацию, но исключает пакет из плана, деплоя, `context.packages`/`context.tags`, проверки `mutex` и расчёта `required_by`. `enable`/`disable` меняют только этот флаг.
- Реализовать проверку `mutex`: если несколько активных пакетов объявляют один и тот же `mutex` — возвращать `AmbiguityError`.
- Добавить валидацию аргументов пакета (`[package.arguments]`) против его `schema.json` и генерацию `~/.config/kaizen/context.json` с Feature Propagation (`context.packages`, `context.tags`).

### Шаг 4. Менеджер источников, `[privacy]`, `kaizen.lock` и проверка обновлений
- Реализовать скачивание и кэширование git-репозиториев пакетов в `~/.local/share/kaizen/sources/`.
- Внедрить фильтры безопасности из `[privacy]`: `quarantine` (выбор коммита старше порога, например `1w`), `foss` (проверка лицензии) и `check-hash`.
- Реализовать чтение и запись `kaizen.lock`.
- **Движок проверки обновлений (Update Engine):**
  - опрос удалённых репозиториев (`git ls-remote` / fetch тегов) для выявления свежих ревизий;
  - фильтрация новых версий через окно `quarantine`;
  - сопоставление с текущим `kaizen.lock` и расчёт доступных обновлений.

### Шаг 5. Сборка пакетов, Бэкапы (`[backup]`) и деплой в `$HOME`
- Поддержать формирование выходной папки пакета `out/` (копирование/шаблоны из `[[package.files]]` с резолвингом per-OS `target` или запуск `build-script` с `context.json`).
- Реализовать **Backup Engine**:
  - перед перезаписью существующих файлов в `~/.config` автоматически сохранять оригинал в `~/.local/share/kaizen/backups/<timestamp>/` с ротацией по `max-generations`.
- Реализовать двухфазный деплой в `kaizen-core`:
  1. `core.plan()` — считает диффы, проверяет коллизии между пакетами и сверяет `sha256` файлов на диске со `state.json`, возвращая список конфликтов (`FileModifiedByUser`, `UnmanagedExistingFile`, `PackageCollision`, `MutexAmbiguity`).
  2. `core.apply(plan, resolutions)` — делает бэкап и атомарно применяет изменения согласно ответам, полученным от CLI/TUI/GUI.

### Шаг 6. Учёт системных зависимостей (Reference Counting) и индексация по `tags`
- Собрать требуемые системные пакеты со всех активных модулей под текущую ОС.
- Пересчитать множество владельцев `required_by` для каждой зависимости в `state.json`:
  - новые зависимости (`required_by` не пуст) → установить через адаптер (`brew`, `dnf`, `apt`, `flatpak`, `mise`);
  - осиротевшие зависимости (`required_by` стал пустым) → включить в `Plan` на удаление.
- Реализовать фильтрацию и поиск пакетов/зависимостей по `tags`.

### Шаг 7. Тонкий CLI и пилотная обкатка
- Поверх `kaizen-core` собрать CLI-клиент:
  - `kaizen bootstrap` — проверка и установка первичных зависимостей ОС (Stage 0);
  - `kaizen install <source> [--type <git|local|url>] [--dry-run]` / `kaizen uninstall <package>` — добавить или удалить декларацию пакета;
  - `kaizen enable <package>` / `kaizen disable <package>` — переключить `enabled` без удаления декларации;
  - `kaizen preset list|add|remove|enable|disable` — управление пресетами;
  - `kaizen sync [--dry-run]` — расчёт плана, интерактивное разрешение конфликтов, бэкап и применение;
  - `kaizen outdated [--deps]` — сравнение `kaizen.lock` с удалёнными апстримами, фильтрация по `quarantine`, отображение таблицы обновлений и changelog; опциональный опрос системных менеджеров (`brew outdated`, `mise outdated`, `dnf check-update`);
  - `kaizen update [pkg] [--sync]` — атомарное обновление записей в `kaizen.lock` до версий, прошедших карантин, с опциональным применением (`--sync`);
  - `kaizen search / list [--tag <tag>]` — поиск пакетов и сквозных зависимостей по тегам;
  - `kaizen backup list / restore <id>` — просмотр и откат снапшотов `~/.config`;
  - `kaizen why <dep|path>` — кто удерживает пакет или владеет файлом;
  - `kaizen doctor` — диагностика окружения.
- Проверить весь цикл на 3 реальных пакетах (`neovim`/`xonsh`, `helix`, `tiling`).
