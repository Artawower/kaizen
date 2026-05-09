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

/// Install packages via the native package manager.
pub trait InstallBackend: Send + Sync {
    fn install(
        &self,
        plan: &WorkflowPlan,
        opts: &SyncOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<InstallReport, KaizenError>;
}

/// Post-apply housekeeping: run `mise install` etc.
pub trait PostApplyBackend: Send + Sync {
    fn post_apply(
        &self,
        opts: &SyncOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<(), KaizenError>;
}

/// Apply dotfiles via chezmoi and produce a preview of apply steps.
pub trait ApplyBackend: Send + Sync {
    fn apply(
        &self,
        plan: &WorkflowPlan,
        opts: &SyncOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<ApplyReport, KaizenError>;

    fn apply_preview(&self, plan: &WorkflowPlan) -> SyncPreview;
}

/// Upgrade packages and mise tools.
pub trait UpdateBackend: Send + Sync {
    fn update(
        &self,
        plan: &WorkflowPlan,
        opts: &UpdateOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<UpdateReport, KaizenError>;
}

/// Clean caches: Nix GC, OS package cache, Docker.
pub trait CleanBackend: Send + Sync {
    fn clean(&self, opts: &CleanOpts) -> Result<CleanReport, KaizenError>;
}

/// Preview install + apply + post-apply steps without executing.
pub trait PreviewBackend: Send + Sync {
    fn preview(&self, plan: &WorkflowPlan) -> SyncPreview;
}

/// Composed backend: install + apply + post-apply + update + clean + preview.
///
/// CLI and Tauri call `detect_backend()` and always receive a `Box<dyn SyncBackend>`.
/// Individual commands depend only on the narrower sub-trait they actually need.
pub trait SyncBackend:
    InstallBackend + ApplyBackend + PostApplyBackend + UpdateBackend + CleanBackend + PreviewBackend
{
    fn id(&self) -> &'static str;

    /// Default: install → apply → post_apply.
    /// NixSyncBackend overrides to: apply → install → post_apply.
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
}
