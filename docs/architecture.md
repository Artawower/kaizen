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
    data["~/.config/kaizen/data.toml<br/>(feature enables, written by kaizen)"]

    subgraph flake["flake.nix"]
        darwin_cfg["darwinConfigurations<br/>(nix-darwin, macOS only)"]
        hm_mac["homeConfigurations.user@mac<br/>(home-manager)"]
        hm_linux["homeConfigurations.user@linux<br/>(home-manager)"]
    end

    subgraph darwin_tree["nix-darwin eval tree"]
        darwin_nix["darwin.nix<br/>system defaults, pam, loginItems"]
        brew["homebrew.casks/brews<br/>feature-conditional"]
        darwin_nix --> brew
    end

    subgraph hm_tree["home-manager eval tree (shared modules)"]
        host["hosts/mac.nix or linux.nix<br/>stateVersion, username, homeDir"]
        mod["modules/darwin.nix or linux.nix"]
        options["options.nix<br/>conf.features · conf.packages · conf.featureRegistry"]
        loader["feature-loader.nix<br/>readDir ./features → imports all *.nix<br/>activation → feature-meta.json"]
        features["features/*.nix<br/>core · helix · vcs · terminal · …"]
        adapter["adapters/home-manager.nix<br/>conf.packages.nix → home.packages"]
        system["system/*.nix<br/>fonts · darkman · battery"]

        host --> mod
        mod --> options
        mod --> loader
        mod --> adapter
        mod --> system
        loader --> features
    end

    data -- "lib.mapAttrs → conf.features.*.enable" --> host
    data -- "features.X or false → homebrew.casks" --> darwin_nix

    darwin_cfg --> darwin_nix
    hm_mac --> host
    hm_linux --> host
```

### Feature module anatomy

Every `features/X.nix` follows this pattern:

```nix
# options.conf.features.X.enable  ←  set by data.toml at eval time

# config = lib.mkMerge [
#   { conf.featureRegistry.X = { description, category } }  ← always
#   (lib.mkIf cfg.enable {                                   ← when enabled
#     conf.packages.nix = [ ... ]                            ← → home.packages
#   })
# ]
```

`conf.featureRegistry` is always populated so `feature-meta.json` contains
the full feature list regardless of what is currently enabled.

### Feature metadata sources

Kaizen CLI priority when showing the wizard:

```
1. ~/.config/kaizen/feature-meta.json   ← live, written by HM activation on every switch
2. dot_config/kaizen/feature-meta.json  ← seed committed in dotfiles, refreshed on configure
```

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
