use std::process::Command;

use crate::{
    backends::common,
    sync_backend::{
        ApplyReport, CleanOpts, CleanReport, InstallReport, SyncOpts, SyncPreview, SyncStep,
        UpdateOpts, UpdateReport,
    },
    KaizenError, SyncBackend, TargetOs, WorkflowPlan,
};

pub struct NixSyncBackend {
    os: TargetOs,
}

impl NixSyncBackend {
    pub fn new(os: TargetOs) -> Self {
        Self { os }
    }

    fn flake_host(&self) -> &'static str {
        match self.os {
            TargetOs::Darwin => "mac",
            _ => "linux",
        }
    }

    fn nix_install_steps(&self) -> Vec<String> {
        let mut steps = vec![];
        if self.os == TargetOs::Darwin {
            steps.push("sudo darwin-rebuild switch --flake ~/.config/nix".into());
        }
        let user = current_user().unwrap_or_else(|_| "<user>".into());
        steps.push(format!(
            "home-manager switch --flake .#{}@{} --impure",
            user,
            self.flake_host()
        ));
        steps
    }
}

impl SyncBackend for NixSyncBackend {
    fn id(&self) -> &'static str {
        "nix"
    }

    fn is_available(&self) -> bool {
        which::which("home-manager").is_ok() || which::which("darwin-rebuild").is_ok()
    }

    fn sync(&self, plan: &WorkflowPlan, opts: &SyncOpts) -> Result<crate::SyncReport, KaizenError> {
        let apply = self.apply(plan, opts)?;
        let install = self.install(plan, opts)?;
        self.post_apply(opts)?;
        Ok(crate::SyncReport { install, apply })
    }

    fn install(&self, _plan: &WorkflowPlan, opts: &SyncOpts) -> Result<InstallReport, KaizenError> {
        let steps = self.nix_install_steps();

        if opts.dry_run {
            return Ok(InstallReport {
                steps,
                warnings: vec![],
            });
        }

        if self.os == TargetOs::Darwin {
            run_darwin_rebuild()?;
        }
        run_home_manager(self.flake_host())?;

        Ok(InstallReport {
            steps,
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
        if opts.update_flake {
            run_nix_flake_update(opts.dry_run)?;
        }

        self.sync(
            plan,
            &SyncOpts {
                dry_run: opts.dry_run,
            },
        )?;

        let tools: Vec<String> = plan.install_plan.mise_tools.keys().cloned().collect();
        if !tools.is_empty() {
            common::mise_upgrade(&tools, opts.dry_run)?;
        }

        Ok(UpdateReport {
            upgraded: vec!["nix (home-manager switch)".into()],
            warnings: vec![],
        })
    }

    fn clean(&self, opts: &CleanOpts) -> Result<CleanReport, KaizenError> {
        let steps = common::clean_steps(&self.os, true);
        if !opts.dry_run {
            run_nix_gc(false)?;
            common::os_cache_clean(&self.os, false)?;
            common::docker_clean(false)?;
        }
        Ok(common::clean_report_from_steps(steps))
    }

    fn preview(&self, plan: &WorkflowPlan) -> SyncPreview {
        let mut steps = vec![SyncStep {
            label: "apply dotfiles".into(),
            command: "chezmoi apply".into(),
        }];

        for s in self.nix_install_steps() {
            steps.push(SyncStep {
                label: "nix switch".into(),
                command: s,
            });
        }

        if which::which("mise").is_ok() {
            steps.push(SyncStep {
                label: "install mise tools".into(),
                command: "mise install".into(),
            });
        }

        let _ = plan;
        SyncPreview { steps }
    }

    fn apply_preview(&self, _plan: &WorkflowPlan) -> SyncPreview {
        let mut steps = vec![SyncStep {
            label: "apply dotfiles".into(),
            command: "chezmoi apply".into(),
        }];
        if which::which("mise").is_ok() {
            steps.push(SyncStep {
                label: "install mise tools".into(),
                command: "mise install".into(),
            });
        }
        SyncPreview { steps }
    }
}

fn current_user() -> Result<String, KaizenError> {
    let out = Command::new("id").arg("-un").output()?;
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_owned())
}

fn nix_config_dir() -> Result<std::path::PathBuf, KaizenError> {
    Ok(dirs::home_dir()
        .ok_or(KaizenError::HomeDirUnavailable)?
        .join(".config/nix"))
}

fn run_darwin_rebuild() -> Result<(), KaizenError> {
    let flake = nix_config_dir()?;
    let status = Command::new("sudo")
        .args(["darwin-rebuild", "switch", "--flake"])
        .arg(&flake)
        .status()?;
    if !status.success() {
        return Err(KaizenError::CommandFailed {
            cmd: "darwin-rebuild switch".into(),
            code: status.code(),
        });
    }
    Ok(())
}

fn run_home_manager(host: &str) -> Result<(), KaizenError> {
    let user = current_user()?;
    let flake = format!(".#{}@{}", user, host);
    let status = Command::new("home-manager")
        .args(["switch", "--flake", &flake, "--impure"])
        .status()?;
    if !status.success() {
        return Err(KaizenError::CommandFailed {
            cmd: "home-manager switch".into(),
            code: status.code(),
        });
    }
    Ok(())
}

fn run_nix_flake_update(dry_run: bool) -> Result<(), KaizenError> {
    if dry_run {
        return Ok(());
    }
    let nix_dir = dirs::home_dir()
        .map(|h| h.join(".config/nix"))
        .unwrap_or_default();
    let status = Command::new("nix")
        .args(["flake", "update", "--flake"])
        .arg(&nix_dir)
        .status()?;
    if !status.success() {
        return Err(KaizenError::CommandFailed {
            cmd: "nix flake update".into(),
            code: status.code(),
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        plan::{ConfigPlan, HookPlan, InstallPlan},
        sync_backend::SyncOpts,
        UserSettings,
    };
    use indexmap::IndexMap;

    fn empty_plan(os: TargetOs) -> WorkflowPlan {
        WorkflowPlan::new(
            os,
            vec![],
            InstallPlan {
                programs: vec![],
                mise_tools: IndexMap::new(),
            },
            ConfigPlan {
                backend: "chezmoi".into(),
                dotfiles_source: None,
                features_data: IndexMap::new(),
                settings: UserSettings { layout: None },
            },
            HookPlan::default(),
            vec![],
        )
    }

    #[test]
    fn flake_host_is_mac_on_darwin() {
        assert_eq!(NixSyncBackend::new(TargetOs::Darwin).flake_host(), "mac");
    }

    #[test]
    fn flake_host_is_linux_on_fedora() {
        assert_eq!(NixSyncBackend::new(TargetOs::Fedora).flake_host(), "linux");
    }

    #[test]
    fn flake_host_is_linux_on_ubuntu() {
        assert_eq!(NixSyncBackend::new(TargetOs::Ubuntu).flake_host(), "linux");
    }

    #[test]
    fn install_dry_run_returns_steps_without_spawning() {
        let backend = NixSyncBackend::new(TargetOs::Darwin);
        let plan = empty_plan(TargetOs::Darwin);
        let report = backend.install(&plan, &SyncOpts { dry_run: true }).unwrap();
        assert!(!report.steps.is_empty());
    }

    #[test]
    fn install_dry_run_darwin_steps_include_darwin_rebuild() {
        let backend = NixSyncBackend::new(TargetOs::Darwin);
        let plan = empty_plan(TargetOs::Darwin);
        let report = backend.install(&plan, &SyncOpts { dry_run: true }).unwrap();
        assert!(
            report.steps.iter().any(|s| s.contains("darwin-rebuild")),
            "darwin steps must include darwin-rebuild, got: {report:?}"
        );
    }

    #[test]
    fn install_dry_run_linux_steps_skip_darwin_rebuild() {
        let backend = NixSyncBackend::new(TargetOs::Linux);
        let plan = empty_plan(TargetOs::Linux);
        let report = backend.install(&plan, &SyncOpts { dry_run: true }).unwrap();
        assert!(
            report.steps.iter().all(|s| !s.contains("darwin-rebuild")),
            "linux steps must not include darwin-rebuild"
        );
    }

    #[test]
    fn apply_preview_contains_chezmoi_apply() {
        let backend = NixSyncBackend::new(TargetOs::Darwin);
        let plan = empty_plan(TargetOs::Darwin);
        let preview = backend.apply_preview(&plan);
        assert!(
            preview
                .steps
                .iter()
                .any(|s| s.command.contains("chezmoi apply")),
            "apply_preview must include chezmoi apply"
        );
    }

    #[test]
    fn apply_preview_does_not_contain_nix_switch() {
        let backend = NixSyncBackend::new(TargetOs::Darwin);
        let plan = empty_plan(TargetOs::Darwin);
        let preview = backend.apply_preview(&plan);
        assert!(
            preview
                .steps
                .iter()
                .all(|s| !s.command.contains("home-manager")
                    && !s.command.contains("darwin-rebuild")),
            "apply_preview must not include nix switch steps"
        );
    }

    #[test]
    fn clean_dry_run_returns_nix_steps() {
        let backend = NixSyncBackend::new(TargetOs::Darwin);
        let report = backend.clean(&CleanOpts { dry_run: true }).unwrap();
        assert!(
            report
                .steps
                .iter()
                .any(|s| s.contains("nix-collect-garbage")),
            "nix clean steps must include nix-collect-garbage"
        );
    }
}

fn run_nix_gc(dry_run: bool) -> Result<(), KaizenError> {
    if dry_run {
        return Ok(());
    }
    let status = Command::new("nix-collect-garbage")
        .args(["--delete-older-than", "7d"])
        .status()?;
    if !status.success() {
        return Err(KaizenError::CommandFailed {
            cmd: "nix-collect-garbage".into(),
            code: status.code(),
        });
    }
    let optimise = Command::new("nix-store").arg("--optimise").status();
    match optimise {
        Ok(s) if s.success() => {}
        Ok(s) => {
            return Err(KaizenError::CommandFailed {
                cmd: "nix-store --optimise".into(),
                code: s.code(),
            });
        }
        Err(e) => return Err(KaizenError::Io(e)),
    }
    Ok(())
}
