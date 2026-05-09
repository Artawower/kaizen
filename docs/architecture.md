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
    START([detect_backend]) --> NIX{home-manager\nor darwin-rebuild\non PATH?}
    NIX -- yes --> NIXBE["NixSyncBackend\napply → install → post_apply\n(chezmoi before home-manager reads it)"]
    NIX -- no --> UPTBE["UptSyncBackend\ninstall → apply → post_apply"]
```

Step order differs: Nix runs `chezmoi apply` first so `.chezmoidata.toml` exists when `home-manager switch` reads it.

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

## WorkflowPlan

```
WorkflowPlan
├── install_plan  — OS packages + mise dev tools
├── config_plan   — dotfiles backend ("chezmoi"), source URL, feature flags, settings
└── hook_plan     — post_install / post_apply / post_update shell commands
```

## Setup Flow

`kaizen install` / `kaizen configure` use `ChezmoiBootstrapper` (in core) for source-dir inspection, backup, and rollback — isolated from the main sync pipeline.

## Testing

All ports have no-op / in-memory implementations (`NoopExecutor`, `NoopChezmoiClient`, `MemFileSystem`). CLI commands expose `run_with(..., backend: &dyn SubTrait)` for injection — tests never spawn processes or touch disk.
