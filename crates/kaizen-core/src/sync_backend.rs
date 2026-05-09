use crate::{progress::ProgressReporter, KaizenError, WorkflowPlan};

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
    fn install(
        &self,
        plan: &WorkflowPlan,
        opts: &SyncOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<InstallReport, KaizenError>;

    /// Step 2 of sync: apply dotfiles.
    fn apply(
        &self,
        plan: &WorkflowPlan,
        opts: &SyncOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<ApplyReport, KaizenError>;

    /// Step 3 of sync: post-apply tasks.
    fn post_apply(
        &self,
        opts: &SyncOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<(), KaizenError>;

    /// Full sync with the correct step order for each backend.
    fn sync(
        &self,
        plan: &WorkflowPlan,
        opts: &SyncOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<SyncReport, KaizenError> {
        let install = self.install(plan, opts, reporter)?;
        let apply = self.apply(plan, opts, reporter)?;
        self.post_apply(opts, reporter)?;
        Ok(SyncReport { install, apply })
    }

    /// Upgrade packages.
    fn update(
        &self,
        plan: &WorkflowPlan,
        opts: &UpdateOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<UpdateReport, KaizenError>;

    /// Clean caches: nix GC, OS package cache, docker.
    fn clean(&self, opts: &CleanOpts) -> Result<CleanReport, KaizenError>;

    /// Preview steps without executing (for dry-run and future `kaizen plan`).
    fn preview(&self, plan: &WorkflowPlan) -> SyncPreview;

    /// Preview only the apply + post-apply steps (dotfiles + mise).
    fn apply_preview(&self, plan: &WorkflowPlan) -> SyncPreview;
}
