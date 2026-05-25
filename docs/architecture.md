# Kaizen Architecture

Kaizen is a headless workflow orchestrator: manages dotfiles, packages, and dev tooling across macOS and Linux. Two-crate workspace — `kaizen-core` (pure library) and `kaizen-cli` (binary that wires concrete OS adapters).

## Layer Diagram

```mermaid
graph TD
    subgraph CLI["kaizen-cli"]
        CMD["Commands<br/>install · configure · sync · apply<br/>update · clean · uninstall · doctor"]
        ROOT["Composition Root<br/>detect_backend()<br/>main.rs"]
        ADAPTERS["Concrete Adapters<br/>StdProcessExecutor · StdFileSystem<br/>StdChezmoiClient · StdPathProvider<br/>UptInstaller · MiseToolchain · DockerCleaner"]
    end

    subgraph CORE["kaizen-core"]
        ENGINE["KaizenEngine<br/>load_config · build_workflow_plan"]
        PLAN["merge::build_plan()<br/>WorkflowPlan"]
        BACKENDS["SyncBackend impls<br/>NixSyncBackend · UptSyncBackend"]
        RUNTIME["Runtime<br/>executor · fs · chezmoi · paths · pm"]
        PORTS["Ports (traits)<br/>ProcessExecutor · FileSystem<br/>ChezmoiClient · PathProvider<br/>DevToolsManager · ContainerCleaner"]
    end

    OS["OS / External Tools<br/>chezmoi · home-manager · nix<br/>upt · mise · docker"]

    CMD --> ENGINE
    CMD --> ROOT
    ROOT --> ADAPTERS
    ADAPTERS --> RUNTIME
    RUNTIME --> BACKENDS
    ENGINE --> PLAN
    PLAN --> BACKENDS
    BACKENDS --> PORTS
    PORTS -.->|implemented by| ADAPTERS
    ADAPTERS --> OS
```

Core backends call ports (traits), never OS directly. All `which` / `std::process` calls are in CLI adapters. `TargetOs::detect()` is the single exception — it queries `os_info` in core for convenience.

## Composition Root

`backend.rs` in CLI constructs all concrete adapters and injects them:

```
detect_backend(os)
  └─ Runtime { StdProcessExecutor, StdFileSystem, StdChezmoiClient, StdPathProvider, pm }
  └─ NixSyncBackend(os, runtime, MiseToolchain, DockerCleaner)
  └─ UptSyncBackend(os, runtime, UptInstaller, MiseToolchain, DockerCleaner)
```

## Data Flow

```mermaid
sequenceDiagram
    participant User
    participant CLI as kaizen-cli
    participant Engine as KaizenEngine
    participant Plan as build_plan()
    participant Backend as SyncBackend

    User->>CLI: kaizen sync
    CLI->>Engine: load_config(path)
    Engine->>Plan: build_workflow_plan(config, os)
    Plan-->>CLI: WorkflowPlan
    CLI->>CLI: detect_backend(os) → Box<dyn SyncBackend>
    CLI->>Backend: sync(plan, opts, StderrReporter)
    Backend-->>User: progress via ProgressReporter
```

`ProgressReporter` is injected by CLI (`StderrReporter`); core never prints directly.

## Backend Selection

```mermaid
flowchart LR
    START([detect_backend]) --> NIX{home-manager<br/>or darwin-rebuild<br/>on PATH?}
    NIX -- yes --> NIXBE["NixSyncBackend<br/>apply → install → post_apply<br/>(chezmoi before home-manager reads it)"]
    NIX -- no --> UPTBE["UptSyncBackend<br/>install → apply → post_apply"]
```

Step order differs: Nix runs `chezmoi apply` first so `~/.config/kaizen/data.toml` is written before `home-manager switch` reads it.

## SyncBackend Trait Hierarchy

```mermaid
classDiagram
    class SyncBackend {
        <<trait>>
        +id() str
        +sync(plan, opts, reporter)
    }
    class InstallBackend { +install() }
    class ApplyBackend { +apply() · +apply_preview() }
    class PostApplyBackend { +post_apply() }
    class UpdateBackend { +update() }
    class CleanBackend { +clean() }
    class PreviewBackend { +preview() }

    SyncBackend --|> InstallBackend
    SyncBackend --|> ApplyBackend
    SyncBackend --|> PostApplyBackend
    SyncBackend --|> UpdateBackend
    SyncBackend --|> CleanBackend
    SyncBackend --|> PreviewBackend

    NixSyncBackend ..|> SyncBackend
    UptSyncBackend ..|> SyncBackend
```

Each CLI command depends only on the narrowest sub-trait it needs.

## Command → Sub-trait Mapping

| Command     | Depends on                           |
| ----------- | ------------------------------------ |
| `sync`      | `SyncBackend` (full)                 |
| `apply`     | `ApplyBackend + PostApplyBackend`    |
| `update`    | `UpdateBackend`                      |
| `clean`     | `CleanBackend`                       |
| `install`   | CLI orchestration (configure → sync) |
| `configure` | `ChezmoiBootstrapper` + wizard       |

## kaizen bump

`kaizen bump` is the repository update command for lock files and tool caches.
It runs bump workflows declared in the Nix `featureRegistry` for each enabled feature.

`kaizen bump` executes enabled feature bump workflows in category order:
**dev → system → other → ai**.

dev/toolchain features run first so tools (e.g. `pi` via mise) are upgraded
before AI extension updates that depend on them.

```mermaid
flowchart TD
    start([kaizen bump]) --> config["Load config.toml enabled features"]
    config --> registry["Read featureRegistry bump workflows"]
    registry --> before["Run bump.before hooks per feature"]
    before --> run["Run bump.run hooks per feature"]
    run --> capture["chezmoi re-add bump.capture paths"]
    capture --> done([done])
```

Each enabled feature can declare a `bump` workflow in its Nix module:

```nix
conf.featureRegistry.mise = {
  bump = {
    before = [{ run = [ "mise" "install" ]; onFailure = "fail"; }];
    run    = [{ run = [ "~/.config/scripts/mise-bump" ]; onFailure = "fail"; }];
    capture = [ "~/.config/mise.lock" ];
  };
};
```

The feature name is the stable selector used by `--only`. `run` is the command argv.
`capture` lists paths passed to `chezmoi re-add` after the commands complete;
paths beginning with `~/` are expanded to the user's home directory.

The mise step calls `~/.config/scripts/mise-bump` instead of plain
`mise upgrade`. The script runs `mise upgrade --bump --interactive`, which opens
a checklist of tools with available updates. The user chooses what to bump each
time, so no hidden deny-list has to be maintained.

After mise updates the rendered `~/.config/mise.toml`, the script reads the
selected bumped versions, writes concrete versions back into the chezmoi template
`~/.local/share/chezmoi/dot_config/mise.toml.tmpl`, skips `latest` and `lts`
selectors, then runs `chezmoi apply` so the rendered config matches the updated
template. Exact pins such as `gopls = "0.20.0"` are bumped only when selected in
the interactive checklist.

`kaizen update` also runs the `update` hooks declared in each enabled feature's
`conf.featureRegistry.<feature>.update` list after the backend completes:

```nix
conf.featureRegistry.ai = {
  description = "AI coding agents and tooling";
  category = "ai";
  update = [
    { run = [ "pi" "update" "--extensions" ]; onFailure = "warn"; }
  ];
};
```

`kaizen re-add` runs only the `bump.capture` paths (no `bump.before` / `bump.run`).
Useful when lock files changed outside of `kaizen bump`.

`onFailure = "warn"` prints a warning and continues. `onFailure = "fail"` stops
the workflow. `--dry-run` prints commands without executing. `--only <feature>`
scopes bump/re-add to a single feature by name.

## Keybindings Catalog

`keybindings.toml` is the lightweight source of truth for user-editable action shortcuts.
It is exported during apply/sync into `.chezmoidata.toml` under `[kaizen.shortcuts]`
for use in chezmoi templates. `keybindings.toml` applies on: `kaizen apply`, `kaizen sync`.

Legacy `mnemonics.toml` is read as a fallback when `keybindings.toml` is absent,
preserving backward compatibility.

## Feature Declaration and Package Flow

### The cycle

`features/*.nix` is the single source of truth. Everything flows from it and
returns to it.

```mermaid
graph LR
    nix["features/*.nix<br/>conf.featureRegistry"]
    json["feature-meta.json<br/>CLI-readable cache"]
    wizard["kaizen configure<br/>wizard"]
    data["data.toml<br/>user's choice"]
    eval["home-manager switch<br/>Nix eval"]

    nix -- "activation script" --> json
    json -- "shows features" --> wizard
    wizard -- "writes" --> data
    data -- "conf.features.*.enable" --> eval
    eval -- "installs packages from" --> nix
```

`feature-meta.json` is a bridge — Rust cannot read `.nix` files, so
`home-manager` activation serialises `conf.featureRegistry` to JSON after
every switch. On a fresh machine (before the first switch) a committed seed
`dot_config/kaizen/feature-meta.json` is used instead and refreshed from the
cloned source on every `kaizen configure`.

### Nix evaluation trees

There are two separate Nix evaluation contexts, both reading `data.toml` as
their only shared runtime input.

```mermaid
graph TD
    data["~/.config/kaizen/data.toml<br/>(feature enables + [extra], written by kaizen)"]
    user_nix["~/.config/kaizen/user-features/*.nix<br/>user feature recipes (primary) / legacy HM modules"]
    user_darwin["~/.config/kaizen/user-features/*.darwin.nix<br/>legacy user darwin attrs (deprecated)"]

    subgraph flake["flake.nix"]
        darwin_cfg["darwinConfigurations<br/>(nix-darwin, macOS only)"]
        hm_mac["homeConfigurations.user@mac<br/>(home-manager)"]
        hm_linux["homeConfigurations.user@linux<br/>(home-manager)"]
    end

    subgraph darwin_tree["nix-darwin eval tree"]
        darwin_nix["darwin.nix<br/>system defaults, pam, loginItems"]
        brew["homebrew.casks/brews<br/>feature-conditional + extra + user-features"]
        darwin_nix --> brew
    end

    subgraph hm_tree["home-manager eval tree (shared modules)"]
        host["hosts/mac.nix or linux.nix<br/>stateVersion, username, homeDir, conf.extra"]
        mod["modules/darwin.nix or linux.nix"]
        options["options.nix<br/>conf.features · conf.packages · conf.featureRegistry · conf.extra"]
        loader["feature-loader.nix<br/>readDir ./features → mkRecipeModule per .nix<br/>readDir user-features → recipe or legacy HM module<br/>activation → feature-meta.json + darwin-deps.json"]
        features["features/*.nix<br/>core · helix · vcs · terminal · …"]
        adapter["adapters/home-manager.nix<br/>conf.packages.nix + conf.extra.nixPackages → home.packages"]
        system["system/*.nix<br/>fonts · darkman · battery"]

        host --> mod
        mod --> options
        mod --> loader
        mod --> adapter
        mod --> system
        loader --> features
    end

    data -- "lib.mapAttrs → conf.features.*.enable" --> host
    data -- "[extra] → conf.extra.*" --> host
    data -- "features.X or false → homebrew.casks/brews" --> darwin_nix
    data -- "[extra].brew_* → homebrew" --> darwin_nix
    user_nix -- "auto-imported" --> loader
    user_darwin -- "auto-imported" --> darwin_nix

    darwin_cfg --> darwin_nix
    hm_mac --> host
    hm_linux --> host
```

### Feature recipe anatomy

Every `features/X.nix` is a **pure function** returning a plain attrset — no
`options`, `config`, or `lib.mkIf` boilerplate:

```nix
{ pkgs, lib, ... }:
{
  description = "My feature";
  category    = "dev";

  packages.nix          = with pkgs; [ ripgrep ];
  packages.darwin.casks = [ "my-cask" ];

  activation.darwin.myScript = ''echo "setup"'';
}
```

`feature-loader.nix` imports each recipe and generates the HM module
centrally: it declares `conf.features.<name>.enable`, registers metadata in
`conf.featureRegistry.<name>`, and conditionally applies packages and
activation scripts when the feature is enabled.

`conf.featureRegistry` is always populated so `feature-meta.json` contains
the full feature list regardless of what is currently enabled.

### Feature metadata sources

Kaizen CLI priority when showing the wizard:

```
1. ~/.config/kaizen/feature-meta.json   ← live, written by HM activation on every switch
2. dot_config/kaizen/feature-meta.json  ← seed committed in dotfiles, refreshed on configure
```

## User Extensibility

Kaizen provides two escape hatches for user-specific customisation that survive
`kaizen configure` re-runs and dotfiles updates.

### `[extra]` in `config.toml`

For quick additions without writing Nix. Edit `~/.config/kaizen/config.toml`
manually after running the wizard. On the next `kaizen sync` the section is
propagated into `data.toml` (which Nix reads):

```
config.toml  →  kaizen sync (merge_kaizen_data_with)  →  data.toml  →  Nix eval
```

```toml
[extra]
nix_packages  = ["ripgrep", "bat"]         # top-level nixpkgs attribute names
brew_casks    = ["istat-menus"]            # homebrew casks (macOS)
brew_formulas = ["ffmpeg"]                # homebrew formulas (macOS)
brew_taps     = ["homebrew/cask-fonts"]   # homebrew taps (macOS)
```

`nix_packages` entries must be valid top-level `nixpkgs` attribute names
(e.g. `"nodejs_22"`, not `"nodePackages.prettier"`). An unknown name produces
a clear Nix eval error with the attribute name. The wizard never touches
`[extra]` — it is preserved verbatim across `kaizen configure` re-runs.

### `user-features/*.nix`

For users comfortable with Nix. Place _recipe_ files in
`~/.config/kaizen/user-features/`. They are auto-discovered alongside built-in
feature recipes and use the same recipe format: `{ pkgs, lib, user ? {}, ... }:`
returning a plain attrset with `description`, `category`, `packages`, etc.

```
~/.config/kaizen/user-features/
  mytools.nix          ← recipe file (same format as built-in features)
```

See `docs/feature-format.org` for the full recipe field reference.

**One feature = one file.** Darwin-specific deps are declared in
`packages.darwin.*` and `activation.darwin`; the loader applies them only on
Darwin. No `lib.optionals pkgs.stdenv.isDarwin` needed in recipe files.

The `*.darwin.nix` pattern is **deprecated and removed**.

### JSON-bridge (HM → nix-darwin)

nix-darwin and Home Manager use separate module-system evaluations. Feature
modules live in the HM evaluation and cannot be imported directly by
nix-darwin. The bridge works in two steps:

1. **HM activation** (`generateDarwinDeps`): writes
   `~/.config/kaizen/darwin-deps.json` from `config.conf.packages.darwin*`
   and `config.conf.darwin.activationScripts` during every `home-manager switch`.
2. **nix-darwin rebuild**: `darwin.nix` reads that JSON with
   `builtins.fromJSON (builtins.readFile darwinDepsPath)` and merges the
   values into `homebrew.*` and `system.activationScripts`.

> **Two-step caveat**: when adding brew deps to a new feature for the first
> time, run `home-manager switch` first (to write the JSON), then
> `darwin-rebuild switch` (to pick it up). `kaizen sync` does both in order.

Both mechanisms require `home-manager switch` / `darwin-rebuild switch` to
take effect (`kaizen sync` triggers this automatically).

## WorkflowPlan

```
WorkflowPlan
├── install_plan  — OS packages + mise dev tools (empty on Nix — managed by Nix)
├── config_plan   — dotfiles backend ("chezmoi"), source URL, feature flags, settings
└── hook_plan     — post_install / post_apply / post_update shell commands
```

## Setup Flow

`kaizen install` / `kaizen configure` use `ChezmoiBootstrapper` (in core) for source-dir inspection, backup, and rollback — isolated from the main sync pipeline.

## Testing

All ports have no-op / in-memory implementations (`NoopExecutor`, `NoopChezmoiClient`, `MemFileSystem`). CLI commands expose `run_with(..., backend: &dyn SubTrait)` for injection — tests never spawn processes or touch disk.
