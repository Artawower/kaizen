# Kaizen: план реализации dependency-layer

## 1. Цель

`kaizen` — это headless dependency orchestrator для установки зависимостей из выбранных пользователем **фич**.

Инструмент должен решать задачу:

```text
Пользователь выбирает фичи:
  frontend, go, python, rust, emacs, helix, ai, mac-gui, etc.

kaizen:
  1. загружает выбранные фичи
  2. учитывает текущую ОС
  3. объединяет backend-specific зависимости
  4. генерирует конфиг для metapac
  5. запускает sync через executor
```

На первом этапе `kaizen` **не является package manager** и **не является resolver-ом уровня Nix**. Он не пытается сам понять, что такое `cargo` на каждой ОС. Вместо этого фичи содержат готовые backend-specific зависимости для `metapac`.

---

## 2. Главный принцип архитектуры

Сначала строится **headless core**, который не зависит от CLI/TUI/GUI.

```text
┌────────────────────┐
│ CLI / TUI / GUI     │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│ kaizen-core       │
│                    │
│ config loading      │
│ feature loading     │
│ OS detection        │
│ merge engine        │
│ plan generation     │
│ manifest generation │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│ executor layer      │
│                    │
│ metapac CLI         │
│ future: direct      │
│ future: nix/brew    │
└────────────────────┘
```

CLI — это только один из интерфейсов. Позже TUI и GUI должны использовать тот же core API.

---

## 3. Что входит в MVP

MVP должен быть максимально простым.

Входит:

```text
- пользовательский config с выбранными фичами
- директория фич
- OS-aware загрузка фич
- merge TOML-файлов
- генерация metapac group-файла
- dry-run / plan
- sync через metapac
- bootstrap unmanaged packages через metapac unmanaged
```

---

## 4. Термины

### Feature

Фича — это пользовательски понятный набор зависимостей.

Примеры:

```text
frontend
python
go
rust
emacs
helix
ai
mac-gui
mac-tiling
linux-desktop
```

Фичи могут пересекаться. Например, `emacs` и `helix` обе могут требовать `ripgrep` и `fd`. Merge engine должен дедуплицировать зависимости.

### Backend

Backend — конкретный package manager / installer, поддерживаемый `metapac`.

Примеры:

```text
brew
mas
mise
cargo
npm
pipx
uv
dnf
flatpak
apt
arch
```

### Generated manifest

Итоговый TOML-файл для `metapac`, сгенерированный из выбранных фич.

---

## 5. Структура репозитория

```text
kaizen/
  crates/
    kaizen-core/
      src/
        lib.rs
        config.rs
        feature.rs
        feature_store.rs
        os.rs
        merge.rs
        plan.rs
        manifest.rs
        executor.rs
        error.rs

    kaizen-cli/
      src/
        main.rs
        commands/
          doctor.rs
          features.rs
          plan.rs
          generate.rs
          sync.rs
          bootstrap.rs

  features/
    core/
      common.toml
      darwin.toml
      fedora.toml
      linux.toml

    frontend/
      common.toml
      darwin.toml
      fedora.toml
      linux.toml

    go/
      common.toml
      darwin.toml
      fedora.toml
      linux.toml

    python/
      common.toml
      darwin.toml
      fedora.toml
      linux.toml

    rust/
      common.toml
      darwin.toml
      fedora.toml
      linux.toml

    emacs/
      common.toml
      darwin.toml
      fedora.toml
      linux.toml

    helix/
      common.toml
      darwin.toml
      fedora.toml
      linux.toml

    ai/
      common.toml
      darwin.toml
      fedora.toml
      linux.toml

  examples/
    config.toml

  docs/
    design.md
    feature-format.md
    roadmap.md
```

---

## 6. Пользовательский config

Файл:

```text
~/.config/kaizen/config.toml
```

MVP-формат:

```toml
features = [
  "core",
  "frontend",
  "go",
  "emacs",
  "ai",
]
```

Позже можно добавить:

```toml
features = [
  "core",
  "frontend",
  "emacs",
]

[settings]
output = "~/.config/metapac/groups/kaizen.generated.toml"
auto_bootstrap_unmanaged = true
```

Но для первого этапа достаточно только `features`.

---

## 7. Формат фич

Фича — это директория с TOML-файлами:

```text
features/<feature-name>/common.toml
features/<feature-name>/darwin.toml
features/<feature-name>/fedora.toml
features/<feature-name>/linux.toml
```

При загрузке фичи kaizen должен брать:

```text
1. common.toml
2. файл текущей ОС, если он существует
```

Например, на macOS:

```text
features/frontend/common.toml
features/frontend/darwin.toml
```

На Fedora:

```text
features/frontend/common.toml
features/frontend/linux.toml
features/frontend/fedora.toml
```

Рекомендуемый порядок merge:

```text
common.toml
linux.toml, если OS является Linux
<os-specific>.toml
```

---

## 8. Примеры фич

### `features/core/common.toml`

```toml
[brew]
packages = [
  "git",
  "ripgrep",
  "fd",
  "fzf",
  "jq",
  "yq",
  "zoxide",
]

[dnf]
packages = [
  "git",
  "ripgrep",
  "fd-find",
  "fzf",
  "jq",
  "yq",
  "zoxide",
]
```

### `features/frontend/common.toml`

```toml
[mise]
packages = [
  { name = "node", options = { version = "22" } },
  { name = "pnpm", options = { version = "latest" } },
]

[npm]
packages = [
  "typescript-language-server",
  "vscode-langservers-extracted",
  "eslint_d",
]
```

### `features/frontend/darwin.toml`

```toml
[brew]
packages = [
  "biome",
]
```

### `features/go/common.toml`

```toml
[mise]
packages = [
  { name = "go", options = { version = "latest" } },
]

[brew]
packages = [
  "gopls",
  "golangci-lint",
]

[dnf]
packages = [
  "gopls",
  "golangci-lint",
]
```

### `features/rust/common.toml`

```toml
[mise]
packages = [
  { name = "rust", options = { version = "stable" } },
]

[cargo]
packages = [
  "cargo-binstall",
  "cargo-watch",
  "cargo-nextest",
]
```

### `features/emacs/darwin.toml`

```toml
[brew]
packages = [
  "emacs",
  "ripgrep",
  "fd",
  "sqlite",
  "imagemagick",
]
```

### `features/helix/common.toml`

```toml
[brew]
packages = [
  "helix",
  "marksman",
]

[dnf]
packages = [
  "helix",
]
```

### `features/ai/darwin.toml`

```toml
[brew]
packages = [
  "ollama",
]

[npm]
packages = [
  "@anthropic-ai/claude-code",
]
```

### `features/mac-gui/darwin.toml`

```toml
[brew]
packages = [
  "aerospace",
]

[brew-cask]
packages = [
  "ghostty",
  "karabiner-elements",
]

[mas]
packages = [
  "497799835",
]
```

---

## 9. Generated metapac manifest

Если пользователь выбрал:

```toml
features = ["core", "frontend", "emacs", "mac-gui"]
```

На macOS kaizen должен сгенерировать:

```toml
# ~/.config/metapac/groups/kaizen.generated.toml
# Generated by kaizen. Do not edit manually.

[brew]
packages = [
  "git",
  "ripgrep",
  "fd",
  "fzf",
  "jq",
  "yq",
  "zoxide",
  "biome",
  "emacs",
  "sqlite",
  "imagemagick",
  "aerospace",
]

[brew-cask]
packages = [
  "ghostty",
  "karabiner-elements",
]

[mise]
packages = [
  { name = "node", options = { version = "22" } },
  { name = "pnpm", options = { version = "latest" } },
]

[npm]
packages = [
  "typescript-language-server",
  "vscode-langservers-extracted",
  "eslint_d",
]

[mas]
packages = [
  "497799835",
]
```

---

## 10. Merge rules

Merge engine должен:

```text
1. объединять backend sections
2. объединять packages внутри backend-а
3. дедуплицировать строковые packages
4. дедуплицировать object packages по name
5. сохранять options для object packages
6. выдавать конфликт, если один и тот же package name указан с разными options
7. сохранять стабильный порядок вывода
```

### Пример дедупликации

Input:

```toml
[brew]
packages = ["ripgrep", "fd"]
```

и:

```toml
[brew]
packages = ["ripgrep", "emacs"]
```

Output:

```toml
[brew]
packages = ["ripgrep", "fd", "emacs"]
```

### Пример конфликта

Input A:

```toml
[mise]
packages = [
  { name = "node", options = { version = "20" } },
]
```

Input B:

```toml
[mise]
packages = [
  { name = "node", options = { version = "22" } },
]
```

Output:

```text
Conflict: package mise:node requested with different options
  frontend/common.toml: version = 22
  legacy-node/common.toml: version = 20
```

---

## 11. Headless core API

Core должен предоставлять API, который можно использовать из CLI, TUI и GUI.

Примерный API:

```rust
pub struct KaizenEngine {
    config_loader: ConfigLoader,
    feature_store: FeatureStore,
    os_detector: OsDetector,
}

impl KaizenEngine {
    pub fn load_config(&self, path: &Path) -> Result<UserConfig>;

    pub fn list_features(&self) -> Result<Vec<FeatureInfo>>;

    pub fn build_plan(&self, request: BuildPlanRequest) -> Result<InstallPlan>;

    pub fn generate_manifest(&self, plan: &InstallPlan) -> Result<GeneratedManifest>;

    pub fn write_manifest(&self, manifest: &GeneratedManifest, path: &Path) -> Result<()>;
}
```

`build_plan` не должен запускать установку. Он только строит данные.

---

## 12. Основные типы

```rust
#[derive(Debug, Clone, Deserialize)]
pub struct UserConfig {
    pub features: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct FeatureInfo {
    pub name: String,
    pub path: PathBuf,
    pub has_common: bool,
    pub has_os_specific: bool,
}

#[derive(Debug, Clone)]
pub struct BuildPlanRequest {
    pub selected_features: Vec<String>,
    pub os: Option<TargetOs>,
}

#[derive(Debug, Clone)]
pub struct InstallPlan {
    pub selected_features: Vec<String>,
    pub target_os: TargetOs,
    pub loaded_files: Vec<PathBuf>,
    pub manifest: MetapacManifest,
    pub warnings: Vec<PlanWarning>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetapacManifest {
    pub backends: BTreeMap<String, BackendSection>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackendSection {
    pub packages: Vec<PackageSpec>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(untagged)]
pub enum PackageSpec {
    Simple(String),
    Detailed {
        name: String,
        #[serde(default)]
        options: BTreeMap<String, toml::Value>,
        #[serde(default)]
        hooks: BTreeMap<String, toml::Value>,
    },
}
```

---

## 13. CLI как thin adapter

CLI не должен содержать бизнес-логику. Он только вызывает core API.

Команды MVP:

```text
kaizen doctor
kaizen features
kaizen plan
kaizen generate
kaizen sync
kaizen bootstrap
```

### `kaizen doctor`

Показывает окружение:

```text
System:
  OS: darwin
  Arch: aarch64

Tools:
  metapac: found
  brew: found
  mas: found
  mise: found
```

### `kaizen features`

Показывает доступные фичи:

```text
Available features:
  core
  frontend
  go
  python
  rust
  emacs
  helix
  ai
  mac-gui
```

### `kaizen plan`

Строит план без записи файлов:

```text
Selected features:
  core
  frontend
  emacs

Loaded files:
  features/core/common.toml
  features/core/darwin.toml
  features/frontend/common.toml
  features/frontend/darwin.toml
  features/emacs/darwin.toml

Generated backends:
  brew: 12 packages
  mise: 2 packages
  npm: 3 packages
```

### `kaizen generate`

Генерирует metapac manifest:

```text
Generated:
  ~/.config/metapac/groups/kaizen.generated.toml
```

### `kaizen sync`

Делает:

```text
1. build plan
2. generate manifest
3. run metapac sync
```

### `kaizen bootstrap`

Первичная настройка:

```text
1. проверяет metapac
2. создает ~/.config/metapac/groups, если нужно
3. если нет 00-unmanaged.toml, выполняет:
   metapac unmanaged > ~/.config/metapac/groups/00-unmanaged.toml
4. генерирует kaizen.generated.toml
5. предлагает выполнить sync
```

---

## 14. Executor layer

На первом этапе нужен только `MetapacCliExecutor`.

```rust
pub trait Executor {
    fn available(&self) -> Result<bool>;
    fn sync(&self) -> Result<ExecutionReport>;
    fn unmanaged(&self) -> Result<String>;
}

pub struct MetapacCliExecutor {
    pub binary: PathBuf,
}
```

Реализация вызывает внешний бинарь:

```text
metapac sync
metapac unmanaged
```

Важно: core не должен напрямую зависеть от CLI executor. Executor — отдельный слой, который может использовать CLI/TUI/GUI.

---

## 15. Bootstrap unmanaged

Проблема:

```text
metapac clean может быть опасен, если не зафиксировать уже установленные пакеты.
```

MVP-решение:

```text
kaizen bootstrap
```

Создает:

```text
~/.config/metapac/groups/00-unmanaged.toml
```

Командой:

```bash
metapac unmanaged > ~/.config/metapac/groups/00-unmanaged.toml
```

Правила:

```text
- не перезаписывать файл, если он уже существует
- для перезаписи требовать --force
- явно предупреждать пользователя, что это snapshot существующих пакетов
```

---

## 16. Почему lock пока не нужен

На старте `kaizen` не обещает воспроизводимость версий.

Фичи описывают desired package list, а actual versions определяются backend-ами:

```text
brew → текущие formula/cask versions
mise → версии, если указаны
npm/cargo → версии, если указаны или latest
mas → текущее состояние App Store
```

Поэтому полноценный lockfile в MVP будет вводить ложное ощущение гарантий.

В будущем можно добавить:

```text
kaizen.resolution.toml
```

который фиксирует:

```text
- выбранные фичи
- загруженные файлы
- сгенерированный manifest hash
- версии, обнаруженные после установки, если возможно
```

Но это не нужно для первой версии.

---

## 17. Почему state пока не нужен

State нужен для safe uninstall.

MVP не должен реализовывать автоматический uninstall, потому что без полноценного ownership tracking легко удалить пользовательские пакеты.

Вместо этого:

```text
- kaizen умеет генерировать и sync-ать зависимости
- metapac unmanaged snapshot защищает уже установленные пакеты
- clean/uninstall не являются частью MVP
```

Позже можно добавить state:

```toml
[packages."brew:emacs"]
existed_before = false
installed_by_kaizen = true
```

Но не раньше, чем появится явная команда uninstall.

---

## 18. Ошибки и предупреждения

Core должен возвращать structured errors, а не печатать строки напрямую.

Типы ошибок:

```text
ConfigNotFound
FeatureNotFound
FeatureFileParseError
MergeConflict
UnsupportedBackendSection
MetapacNotFound
MetapacExecutionFailed
```

Пример ошибки:

```text
Feature not found: frontendx

Available similar features:
  frontend
```

Пример merge conflict:

```text
Conflict in package mise:node

features/frontend/common.toml:
  version = "22"

features/legacy/common.toml:
  version = "20"
```

---

## 19. Конфликт-детектор

Минимальный conflict detection:

```text
- same backend + same package name + different options = error
- same backend + same package name + same options = dedupe
```

Позже можно добавить semantic conflicts:

```text
- node через brew и node через mise одновременно
- rust через brew и rust через mise одновременно
- emacs через brew и emacs через dnf одновременно на одной ОС
```

Но для MVP semantic conflicts можно не делать.

---

## 20. OS detection

Поддерживаемые target OS в MVP:

```text
darwin
fedora
linux
```

`linux` — общий fallback для всех Linux.

Порядок загрузки файлов:

```text
common.toml
linux.toml, если target OS является Linux
<target-os>.toml
```

Примеры:

macOS:

```text
common.toml
darwin.toml
```

Fedora:

```text
common.toml
linux.toml
fedora.toml
```

---

## 21. Будущая TUI

TUI должна использовать core API:

```text
list_features()
build_plan()
generate_manifest()
write_manifest()
executor.sync()
```

TUI-флоу:

```text
1. показать список фич
2. пользователь toggles features
3. показать generated plan
4. показать предупреждения
5. сохранить config.toml
6. выполнить generate/sync
```

TUI не должна знать, как мерджить TOML или как строить plan.

---

## 22. Будущая GUI

GUI должна работать аналогично TUI:

```text
frontend app → calls headless engine / daemon / CLI JSON API
```

Для GUI стоит заранее предусмотреть machine-readable output:

```bash
kaizen plan --json
kaizen features --json
kaizen doctor --json
```

Это позволит GUI не парсить человекочитаемый вывод.

---

## 23. JSON output

CLI должен поддерживать `--json` для команд:

```text
features
doctor
plan
generate
```

Пример:

```bash
kaizen plan --json
```

Output:

```json
{
  "target_os": "darwin",
  "selected_features": ["core", "frontend", "emacs"],
  "loaded_files": [
    "features/core/common.toml",
    "features/core/darwin.toml",
    "features/frontend/common.toml",
    "features/emacs/darwin.toml"
  ],
  "backends": {
    "brew": {
      "packages": ["git", "ripgrep", "fd", "emacs"]
    },
    "mise": {
      "packages": [
        { "name": "node", "options": { "version": "22" } }
      ]
    }
  },
  "warnings": []
}
```

---

## 24. Тестирование

### Unit tests

```text
- parse user config
- discover features
- load common/os-specific files
- merge backend sections
- dedupe simple packages
- dedupe detailed packages
- detect conflict on different options
- generate TOML output
```

### Golden tests

Для каждого кейса:

```text
tests/golden/darwin_frontend_emacs/input/config.toml
tests/golden/darwin_frontend_emacs/expected/metapac.generated.toml
```

Тест:

```text
input config + target OS → generated TOML exactly equals expected
```

### Integration tests

Использовать fake `metapac` binary в PATH.

Проверить:

```text
- kaizen sync вызывает metapac sync
- kaizen bootstrap вызывает metapac unmanaged
- ошибки metapac корректно пробрасываются
```

Не запускать настоящий `metapac sync` в CI.

---

## 25. Roadmap

### Phase 1: headless merge engine

Deliverables:

```text
- kaizen-core crate
- UserConfig parser
- FeatureStore
- OS detection
- TOML merge
- InstallPlan
- manifest generation
```

Success criteria:

```text
Core API может загрузить config и сгенерировать metapac manifest без CLI.
```

---

### Phase 2: CLI MVP

Deliverables:

```text
- kaizen-cli crate
- doctor
- features
- plan
- generate
```

Success criteria:

```text
kaizen plan показывает, какие backend sections и packages будут сгенерированы.
kaizen generate пишет kaizen.generated.toml.
```

---

### Phase 3: metapac executor

Deliverables:

```text
- MetapacCliExecutor
- sync command
- bootstrap command
- unmanaged snapshot
```

Success criteria:

```text
kaizen bootstrap создает 00-unmanaged.toml.
kaizen sync генерирует manifest и вызывает metapac sync.
```

---

### Phase 4: robustness

Deliverables:

```text
- better errors
- --json output
- golden tests
- fake metapac integration tests
- conflict reporting
```

Success criteria:

```text
CLI output пригоден для людей, JSON output пригоден для TUI/GUI.
```

---

### Phase 5: TUI

Deliverables:

```text
- feature selection screen
- plan preview
- save config
- run sync
```

Success criteria:

```text
Пользователь может выбрать фичи без редактирования TOML.
```

---

### Phase 6: future advanced features

Возможные направления:

```text
- state для safe uninstall
- resolution snapshot
- semantic sources
- provider policy
- Nix backend
- direct providers без metapac
- Steel/Scheme provider plugins
- GUI
```

Эти элементы не нужны для MVP и не должны блокировать первый релиз.

---

## 26. Итоговая MVP-команда

Желаемый первый UX:

```bash
kaizen bootstrap
kaizen features
kaizen plan
kaizen generate
kaizen sync
```

Минимальный config:

```toml
features = [
  "core",
  "frontend",
  "emacs",
  "ai",
]
```

Минимальный результат:

```text
kaizen генерирует ~/.config/metapac/groups/kaizen.generated.toml
и запускает metapac sync.
```

---

## 27. Главный критерий успеха

Первая версия успешна, если можно сказать:

```text
Я выбрал фичи frontend + emacs + ai,
получил корректный metapac manifest для моей ОС,
увидел plan,
и одной командой запустил установку зависимостей.
```

Без профилей, без lockfile, без собственного package manager, без сложной policy-системы.

