use std::process::Command;

use crate::{
    backends::common,
    installer::UptInstaller,
    installer::{Installer, Updater},
    sync_backend::{
        ApplyReport, CleanOpts, CleanReport, InstallReport, SyncOpts, SyncPreview, SyncStep,
        UpdateOpts, UpdateReport,
    },
    KaizenError, SyncBackend, TargetOs, WorkflowPlan,
};

pub struct UptSyncBackend {
    os: TargetOs,
}

impl UptSyncBackend {
    pub fn new(os: TargetOs) -> Self {
        Self { os }
    }
}

impl SyncBackend for UptSyncBackend {
    fn id(&self) -> &'static str {
        "upt"
    }

    fn is_available(&self) -> bool {
        which::which("upt").is_ok()
    }

    fn install(&self, plan: &WorkflowPlan, opts: &SyncOpts) -> Result<InstallReport, KaizenError> {
        let programs = &plan.install_plan.programs;
        if programs.is_empty() {
            return Ok(InstallReport::default());
        }

        if opts.dry_run {
            return Ok(InstallReport {
                steps: vec![UptInstaller.preview_install(programs)],
                warnings: vec![],
            });
        }

        UptInstaller.install(programs)?;
        Ok(InstallReport {
            steps: vec![UptInstaller.preview_install(programs)],
            warnings: vec![],
        })
    }

    fn apply(&self, plan: &WorkflowPlan, opts: &SyncOpts) -> Result<ApplyReport, KaizenError> {
        common::chezmoi_write_and_apply(&plan.config_plan, opts.dry_run)
    }

    fn post_apply(&self, opts: &SyncOpts) -> Result<(), KaizenError> {
        if which::which("mise").is_ok() {
            return common::mise_install(opts.dry_run);
        }
        Ok(())
    }

    fn update(&self, plan: &WorkflowPlan, opts: &UpdateOpts) -> Result<UpdateReport, KaizenError> {
        let programs = &plan.install_plan.programs;
        let mut warnings = vec![];

        if !programs.is_empty() {
            if opts.dry_run {
                return Ok(UpdateReport {
                    upgraded: programs.clone(),
                    warnings,
                });
            }
            if let Err(KaizenError::InstallerPartialFailure { failed, .. }) =
                UptInstaller.upgrade(programs)
            {
                warnings.extend(failed.iter().map(|p| format!("{p}: failed to upgrade")));
            }
        }

        let tools: Vec<String> = plan.install_plan.mise_tools.keys().cloned().collect();
        if !tools.is_empty() {
            common::mise_upgrade(&tools, opts.dry_run)?;
        }

        Ok(UpdateReport {
            upgraded: programs.clone(),
            warnings,
        })
    }

    fn clean(&self, opts: &CleanOpts) -> Result<CleanReport, KaizenError> {
        let steps = common::clean_steps(&self.os, false);
        if !opts.dry_run {
            common::os_cache_clean(&self.os, false)?;
            common::docker_clean(false)?;
        }
        Ok(common::clean_report_from_steps(steps))
    }

    fn preview(&self, plan: &WorkflowPlan) -> SyncPreview {
        let mut steps = vec![];

        if !plan.install_plan.programs.is_empty() {
            steps.push(SyncStep {
                label: "install packages".into(),
                command: UptInstaller.preview_install(&plan.install_plan.programs),
            });
        }

        steps.push(SyncStep {
            label: "apply dotfiles".into(),
            command: "chezmoi apply".into(),
        });

        if which::which("mise").is_ok() {
            steps.push(SyncStep {
                label: "install mise tools".into(),
                command: "mise install".into(),
            });
        }

        SyncPreview { steps }
    }
}

/// Запускает `upt upgrade` для всей ОС (без списка пакетов).
#[allow(dead_code)]
pub(crate) fn upt_upgrade_all(dry_run: bool) -> Result<(), KaizenError> {
    if dry_run {
        return Ok(());
    }
    let status = Command::new("upt").args(["upgrade", "-y"]).status()?;
    if !status.success() {
        return Err(KaizenError::CommandFailed {
            cmd: "upt upgrade".into(),
            code: status.code(),
        });
    }
    Ok(())
}
