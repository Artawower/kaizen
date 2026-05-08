use crate::{KaizenError, WorkflowPlan};

#[derive(Debug, Clone, Default)]
pub struct SyncOpts {
    pub dry_run: bool,
}

#[derive(Debug, Clone, Default)]
pub struct UpdateOpts {
    pub dry_run: bool,
    /// Run `nix flake update` before switching (Nix backend only).
    pub update_flake: bool,
}

#[derive(Debug, Clone, Default)]
pub struct CleanOpts {
    pub dry_run: bool,
}

#[derive(Debug, Clone, Default)]
pub struct InstallReport {
    pub steps: Vec<String>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Default)]
pub struct ApplyReport {
    pub data_path: Option<std::path::PathBuf>,
}

#[derive(Debug, Clone, Default)]
pub struct SyncReport {
    pub install: InstallReport,
    pub apply: ApplyReport,
}

#[derive(Debug, Clone, Default)]
pub struct UpdateReport {
    pub upgraded: Vec<String>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Default)]
pub struct CleanReport {
    pub freed_bytes: Option<u64>,
    pub steps: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct SyncStep {
    pub label: String,
    pub command: String,
}

#[derive(Debug, Clone, Default)]
pub struct SyncPreview {
    pub steps: Vec<SyncStep>,
}

/// Full workflow lifecycle abstraction: install + apply + post-apply + update + clean.
///
/// CLI and Tauri both call `detect_backend()` and never depend on a concrete type.
pub trait SyncBackend: Send + Sync {
    fn id(&self) -> &'static str;
    fn is_available(&self) -> bool;

    /// Step 1 of sync: install packages.
    ///
    /// - `UptSyncBackend`: `upt install <programs>`
    /// - `NixSyncBackend`: `darwin-rebuild switch` + `home-manager switch`
    ///   (ignores `plan.install_plan.programs` — Nix reads its own modules)
    ///
    /// Error aborts the whole sync.
    fn install(&self, plan: &WorkflowPlan, opts: &SyncOpts) -> Result<InstallReport, KaizenError>;

    /// Step 2 of sync: apply dotfiles.
    ///
    /// Same for all backends: write `.chezmoidata.toml` → `chezmoi apply`.
    /// Error aborts the whole sync.
    fn apply(&self, plan: &WorkflowPlan, opts: &SyncOpts) -> Result<ApplyReport, KaizenError>;

    /// Step 3 of sync: post-apply tasks.
    ///
    /// Same for all backends: `mise install && mise trust ~/.config/mise.toml`.
    fn post_apply(&self, opts: &SyncOpts) -> Result<(), KaizenError>;

    /// Full sync with the correct step order for each backend.
    ///
    /// Default (upt): install → apply → post_apply
    /// NixSyncBackend overrides to: apply → install → post_apply
    /// (chezmoi apply must run first because Nix reads `.chezmoidata.toml`)
    fn sync(&self, plan: &WorkflowPlan, opts: &SyncOpts) -> Result<SyncReport, KaizenError> {
        let install = self.install(plan, opts)?;
        let apply = self.apply(plan, opts)?;
        self.post_apply(opts)?;
        Ok(SyncReport { install, apply })
    }

    /// Upgrade packages. `opts.update_flake = true` also runs `nix flake update`.
    fn update(&self, plan: &WorkflowPlan, opts: &UpdateOpts) -> Result<UpdateReport, KaizenError>;

    /// Clean caches: nix GC, OS package cache, docker.
    fn clean(&self, opts: &CleanOpts) -> Result<CleanReport, KaizenError>;

    /// Preview steps without executing (for dry-run and future `kaizen plan`).
    fn preview(&self, plan: &WorkflowPlan) -> SyncPreview;

    /// Preview only the apply + post-apply steps (dotfiles + mise).
    /// Used by `kaizen apply --dry-run` to avoid showing install steps.
    fn apply_preview(&self, plan: &WorkflowPlan) -> SyncPreview;
}
