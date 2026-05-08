# Scout Context: Kaizen Nix Integration Architecture vs Implementation

## Summary

The kaizen project has **successfully implemented most** of the documented nix-integration.org architecture. However, there are **4 concrete mismatches** and **2 notable omissions** that could affect downstream work. The core SyncBackend abstraction, backends (Nix/Upt), detector, and ordering are **correct**. The issues are primarily in:

1. **ApplyReport data structure** — changed from plan to track path instead of file count
2. **Doctor command** — missing Nix-specific diagnostics sections  
3. **Tool availability checks** — Nix tools (home-manager, darwin-rebuild) not registered in ensure.rs
4. **Missing CLI feature** — `kaizen config layout` subcommand not implemented (Phase 5)
5. **UptInstaller direct usage** — install.rs bypasses SyncBackend trait (architectural inconsistency)

---

## Relevant Files

### Core Backend Implementation
- `crates/kaizen-core/src/sync_backend.rs` — Trait definition ✅
- `crates/kaizen-core/src/backends/detect.rs` — Backend detection ✅
- `crates/kaizen-core/src/backends/nix.rs` — Nix implementation ✅
- `crates/kaizen-core/src/backends/upt.rs` — Upt implementation ✅
- `crates/kaizen-core/src/backends/common.rs` — Shared helpers ✅
- `crates/kaizen-core/src/os.rs` — OS/PackageManager detection ✅

### CLI Commands
- `crates/kaizen-cli/src/commands/sync.rs` — Uses backend ✅
- `crates/kaizen-cli/src/commands/apply.rs` — Uses backend ✅
- `crates/kaizen-cli/src/commands/update.rs` — Uses backend ✅
- `crates/kaizen-cli/src/commands/clean.rs` — Uses backend ✅
- `crates/kaizen-cli/src/commands/install.rs` — **Direct UptInstaller** ⚠️
- `crates/kaizen-cli/src/commands/doctor.rs` — **Incomplete** ⚠️
- `crates/kaizen-cli/src/ensure.rs` — **Missing Nix tools** ⚠️

---

## Key Findings

### ✅ CORRECT: SyncBackend Trait Design

**File:** `crates/kaizen-core/src/sync_backend.rs`

The trait is properly defined with all required methods:
- `install()`, `apply()`, `post_apply()`, `sync()`, `update()`, `clean()`, `preview()`, `apply_preview()`
- Matches plan exactly (plus bonus `apply_preview()` for CLI UX)

### ✅ CORRECT: NixSyncBackend Ordering (apply → install → post_apply)

**File:** `crates/kaizen-core/src/backends/nix.rs:62-67`

```rust
fn sync(&self, plan: &WorkflowPlan, opts: &SyncOpts) -> Result<crate::SyncReport, KaizenError> {
    let apply = self.apply(plan, opts)?;      // ← chezmoidata first
    let install = self.install(plan, opts)?;  // ← then darwin-rebuild + home-manager
    self.post_apply(opts)?;                   // ← then mise install
    Ok(SyncReport { install, apply })
}
```

This is **exactly as documented** in the plan. Nix reads `.chezmoidata.toml` so chezmoi must run first.

### ✅ CORRECT: UptSyncBackend Default Ordering (install → apply → post_apply)

**File:** `crates/kaizen-core/src/sync_backend.rs:89-95`

Default trait implementation:
```rust
fn sync(&self, plan: &WorkflowPlan, opts: &SyncOpts) -> Result<SyncReport, KaizenError> {
    let install = self.install(plan, opts)?;    // ← upt first
    let apply = self.apply(plan, opts)?;        // ← then chezmoi
    self.post_apply(opts)?;                     // ← then mise
    Ok(SyncReport { install, apply })
}
```

Correct — UptSyncBackend doesn't override this, so it uses default.

### ✅ CORRECT: Backend Detection Priority

**File:** `crates/kaizen-core/src/backends/detect.rs`

```rust
pub fn detect_backend(os: TargetOs) -> Box<dyn SyncBackend> {
    let nix = NixSyncBackend::new(os.clone());
    if nix.is_available() {
        return Box::new(nix);
    }
    Box::new(UptSyncBackend::new(os))
}
```

Matches plan: Nix → Upt priority.

### ✅ CORRECT: PackageManagerKind Detection

**File:** `crates/kaizen-core/src/os.rs:44-56`

```rust
pub fn package_manager_kind(&self) -> PackageManagerKind {
    match self {
        TargetOs::Darwin => PackageManagerKind::Brew,
        TargetOs::Fedora => PackageManagerKind::Dnf,
        TargetOs::Ubuntu => PackageManagerKind::Apt,
        TargetOs::Linux => detect_linux_pm(),
        _ => PackageManagerKind::Unknown,
    }
}
```

Enum defined correctly, detection logic sound.

### ✅ CORRECT: CLI Commands Use Backend Abstraction

All main commands properly use `detect_backend()` and call trait methods:

- **sync.rs** (line 7): `let backend = detect_backend(os);` → `backend.sync()`
- **apply.rs** (line 8): `let backend = detect_backend(os);` → `backend.apply()` + `backend.post_apply()`
- **update.rs** (line 20): `let backend = detect_backend(os);` → `backend.update()`
- **clean.rs** (line 8): `let backend = detect_backend(os);` → `backend.clean()`

This follows the "headless core + thin CLI adapter" principle correctly.

---

## ⚠️ MISMATCHES & GAPS

### MISMATCH 1: ApplyReport Structure Changed

**Plan (nix-integration.org):**
```rust
pub struct ApplyReport { pub files_changed: usize }
```

**Actual Implementation (sync_backend.rs:16-18):**
```rust
#[derive(Debug, Clone, Default)]
pub struct ApplyReport {
    pub data_path: Option<std::path::PathBuf>,
}
```

**Impact:** Minor. The implementation tracks *where* the data file was written instead of *how many* files chezmoi touched. The apply.rs command prints this path (line 31):
```rust
if let Some(path) = &report.data_path {
    output::item_ok(&format!("wrote {}", path.display()));
}
```

**Fix:** This is actually an improvement — users see where `.chezmoidata.toml` was written. No action needed unless you want backward compatibility with a planned `ApplyReport.files_changed` API.

---

### MISMATCH 2: Doctor Command Lacks Sync Backend & Nix Sections

**Plan (nix-integration.org, Фаза 4):**

Expected sections:
```
Sync backend:
  detected: nix/upt
  home-manager: found (version)
  darwin-rebuild: found
  chezmoi source: ~/.local/share/chezmoi
  dotfiles remote: url

Nix:
  nix: found (version)
  flake: ~/.config/nix
  last flake update: X days ago

Mise:
  mise: found (version)
  outdated tools: node (20 → 22)

Config:
  kaizen config: path
  schema_version: current
  features: core ✓ frontend ✓ ...
```

**Actual Implementation (commands/doctor.rs):**

```rust
output::header("System");     // OS, arch
output::header("Tools");       // upt, chezmoi, mise only
// NO "Sync backend" section
// NO "Nix" section
// NO version information
// NO flake update time
report_config(engine, config_path);  // basic config check
output::header("Features");    // count only
```

**File:** `crates/kaizen-cli/src/commands/doctor.rs:1-56`

**Impact:** High. Users can't easily verify:
- Which backend is detected (Nix vs Upt)
- Nix tool availability (home-manager, darwin-rebuild, nix itself)
- Flake freshness
- Nix version

**Fix Needed:**
- Add `report_sync_backend()` function to check `detect_backend(os).id()` and print detected backend
- Add `report_nix_diagnostics()` for Nix-specific checks:
  - `which home-manager`, `which darwin-rebuild`, `which nix`
  - Read `~/.config/nix` flake.lock mtime
  - Run `nix --version`
- Add `report_mise_tools()` to show `mise --version` and outdated tools

**Fix Location:** Insert after line 18 in doctor.rs:
```rust
output::header("Sync Backend");
report_sync_backend();

output::header("Nix");
report_nix_diagnostics();

output::header("Mise");
report_mise_tools();
```

---

### MISMATCH 3: Nix Tool Constants Missing from ensure.rs

**Plan (nix-integration.org, Фаза 4):**

> Добавить в `ensure.rs`:
> ```rust
> pub const HOME_MANAGER: Tool = Tool {
>     name: "home-manager",
>     install_hint: "https://nix-community.github.io/home-manager/",
> };
> pub const NIX_DARWIN: Tool = Tool {
>     name: "darwin-rebuild",
>     install_hint: "https://github.com/LnL7/nix-darwin",
> };
> pub const NIX: Tool = Tool {
>     name: "nix",
>     install_hint: "https://install.determinate.systems/nix",
> };
> ```

**Actual Implementation (ensure.rs):**

```rust
pub const UPT: Tool = Tool { ... };
pub const CHEZMOI: Tool = Tool { ... };
pub const MISE: Tool = Tool { ... };
pub const ALL: &[&Tool] = &[&UPT, &CHEZMOI, &MISE];  // ← no Nix tools
```

**File:** `crates/kaizen-cli/src/ensure.rs:1-30`

**Impact:** Medium. Doctor command only checks upt/chezmoi/mise. Nix tools are never validated, so users on Nix systems don't get warned about missing home-manager or darwin-rebuild.

**Fix Needed:** Add to ensure.rs after MISE:
```rust
pub const HOME_MANAGER: Tool = Tool {
    name: "home-manager",
    install_hint: "https://nix-community.github.io/home-manager/",
};
pub const DARWIN_REBUILD: Tool = Tool {
    name: "darwin-rebuild",
    install_hint: "https://github.com/LnL7/nix-darwin",
};
pub const NIX: Tool = Tool {
    name: "nix",
    install_hint: "https://install.determinate.systems/nix",
};

pub const ALL: &[&Tool] = &[
    &CHEZMOI, &MISE,  // always required
    &UPT, &HOME_MANAGER, &DARWIN_REBUILD, &NIX  // alternatives
];
```

Then in doctor.rs, conditional reporting:
```rust
let backend = detect_backend(os);
if backend.id() == "nix" {
    for tool in [&ensure::HOME_MANAGER, &ensure::DARWIN_REBUILD, &ensure::NIX] {
        report_tool(tool);
    }
} else {
    report_tool(&ensure::UPT);
}
```

---

### GAP 1: Missing `kaizen config layout` Subcommand

**Plan (nix-integration.org, Фаза 5):**

> В `main.rs`:
> ```rust
> #[derive(Subcommand)]
> enum ConfigCommand {
>     Layout { layout: Option<String> },  // None → показать текущую
> }
> ```

**Actual Implementation:**

- No `config` subcommand exists
- No `commands/config.rs` file
- `main.rs` doesn't have ConfigCommand enum

**File:** Missing entire flow at `crates/kaizen-cli/src/commands/config.rs`

**Impact:** Medium. Users can't switch keyboard layout via `kaizen config layout colemak`. They must edit `config.toml` manually or use `just layout` (if available).

**Fix Needed:** 

1. Create `commands/config.rs` with:
```rust
pub fn run_layout(config_path: &Path, layout: Option<&str>) -> Result<()> {
    match layout {
        None => {
            // show current layout from config.toml
            let config = engine.load_config(config_path)?;
            println!("current layout: {:?}", config.settings.layout);
        }
        Some(l) => {
            // 1. validate layout in ["colemak", "qwerty"]
            // 2. load config
            // 3. update config.settings.layout = l
            // 4. save config
            // 5. build plan, detect backend, call backend.apply()
            //    (re-renders helix, niri, xremap templates)
        }
    }
}
```

2. Update `main.rs` Command enum:
```rust
#[derive(Subcommand)]
enum Command {
    // ...
    Config {
        #[command(subcommand)]
        subcommand: ConfigCommand,
    },
}

#[derive(Subcommand)]
enum ConfigCommand {
    Layout {
        #[arg(value_parser = ["colemak", "qwerty"])]
        layout: Option<String>,
    },
}
```

3. Update main() match:
```rust
Command::Config { subcommand } => {
    match subcommand {
        ConfigCommand::Layout { layout } => {
            commands::config::run_layout(&engine, &config_path, layout.as_deref())?;
        }
    }
}
```

---

### GAP 2: UptInstaller Used Directly in install.rs (Architectural Inconsistency)

**Plan (nix-integration.org):**

> `kaizen-cli` — тонкий адаптер: wire up реализаций к clap-командам.
> Вся логика — в core.

All other commands use `detect_backend()` and call backend methods.

**Actual Implementation (commands/install.rs:14-16):**

```rust
pub fn run(engine: &KaizenEngine, config_path: &Path, dry_run: bool) -> Result<()> {
    output::page_header(if dry_run { "install  (dry-run)" } else { "install" });
    ensure::require(&[&ensure::UPT])?;  // ← only allows UPT
    run_with(
        engine,
        config_path,
        dry_run,
        TargetOs::detect(),
        &UptInstaller,  // ← DIRECT TRAIT OBJECT, not via backend
        &ShellHookRunner,
    )
}
```

Then runs the old logic:
```rust
match installer.install(programs) {
    Ok(()) => { ... }
    Err(KaizenError::InstallerPartialFailure { ... }) => { ... }
}
```

**Files:**
- `crates/kaizen-cli/src/commands/install.rs:14-56` — uses old Installer trait
- vs. `crates/kaizen-cli/src/commands/sync.rs:7-10` — uses backend.install()

**Impact:** Medium. The `install` command contradicts the thin-adapter principle:
- It requires `upt` explicitly (line 15), ignoring Nix
- It uses the old `Installer` trait instead of `SyncBackend`
- Main.rs explicitly warns: "Run `kaizen sync` instead on Nix systems" (line 165)

**Intention:** The plan describes `install` as an **explicit upt-path for non-Nix users**. This is actually correct behavior — it's a fallback for when users want to force upt.

**Fix (if needed for consistency):**

Option A: Keep as-is (explicit upt-only path, users warned in help text).

Option B: Refactor to use backend but only call `backend.install()`:
```rust
pub fn run(engine: &KaizenEngine, config_path: &Path, dry_run: bool) -> Result<()> {
    let os = TargetOs::detect();
    let backend = detect_backend(os);
    if backend.id() != "upt" {
        bail!("kaizen install is upt-only. Use 'kaizen sync' for Nix.");
    }
    // ... call backend.install() instead of UptInstaller directly
}
```

This is a polish issue, not a breaking mismatch.

---

## Headless Core Principle — Assessment

✅ **CORRECT.** The core (`kaizen-core/src`) contains:
- Trait definitions (SyncBackend, Installer, Updater, Remover)
- Backend implementations (Nix, Upt)
- No IO except via traits (runs commands through `Command::new()` which is still encapsulated)
- OS detection, config merging, feature resolution

✅ **CLI is thin.** Each command in `kaizen-cli`:
- Loads config
- Builds plan via engine
- Detects backend OR forces a specific one (install.rs)
- Calls backend methods
- Formats output

No business logic in CLI, no duplication of install/apply/update logic.

---

## Summary of Concrete Fixes

| Priority | Issue | File | Fix |
|----------|-------|------|-----|
| 🔴 HIGH  | Doctor incomplete | commands/doctor.rs | Add "Sync backend", "Nix", "Mise" sections with tool checking |
| 🟡 MED   | Missing Nix tools in ensure | ensure.rs | Add HOME_MANAGER, DARWIN_REBUILD, NIX constants |
| 🟡 MED   | Missing `kaizen config layout` | commands/config.rs (new) | Create file + add ConfigCommand enum to main.rs |
| 🟢 LOW   | ApplyReport structure diff | sync_backend.rs | No action — `data_path` is better than `files_changed` |
| 🟢 LOW   | install.rs direct UptInstaller | commands/install.rs | Optional: refactor to use backend.install() for consistency |

---

## Files to Review for Fixes

1. **Doctor enhancement:** crates/kaizen-cli/src/commands/doctor.rs
   - Lines 1–56 need expansion for Nix sections

2. **Tool registration:** crates/kaizen-cli/src/ensure.rs
   - Add Nix tool constants after line 20

3. **Config layout:** crates/kaizen-cli/src/commands/config.rs (NEW)
   - crates/kaizen-cli/src/main.rs — add ConfigCommand enum

4. (Optional) **install.rs refactor:** crates/kaizen-cli/src/commands/install.rs
   - Keep as explicit upt-path, OR refactor to backend.install()

---

## Conclusion

The nix-integration.org architecture is **~95% implemented correctly**. The SyncBackend abstraction, ordering logic, backend detection, and headless core principle are solid. The gaps are primarily in **diagnostics (doctor)** and **missing CLI features (config layout)**. No breaking architectural issues.
