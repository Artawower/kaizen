use crate::{
    backends::common,
    container::ContainerCleaner,
    executor::ProcessCommand,
    progress::ProgressReporter,
    runtime::Runtime,
    sync_backend::{
        ApplyBackend, ApplyReport, CleanBackend, CleanOpts, CleanReport, InstallBackend,
        InstallReport, PostApplyBackend, PreviewBackend, SyncOpts, SyncPreview, SyncStep,
        UpdateBackend, UpdateOpts, UpdateReport,
    },
    toolchain::DevToolsManager,
    KaizenError, SyncBackend, TargetOs, WorkflowPlan,
};

pub struct NixSyncBackend {
    os: TargetOs,
    runtime: Runtime,
    dev_tools: Box<dyn DevToolsManager>,
    container: Box<dyn ContainerCleaner>,
}

impl NixSyncBackend {
    pub fn new(
        os: TargetOs,
        runtime: Runtime,
        dev_tools: Box<dyn DevToolsManager>,
        container: Box<dyn ContainerCleaner>,
    ) -> Self {
        Self {
            os,
            runtime,
            dev_tools,
            container,
        }
    }

    fn flake_host(&self) -> &'static str {
        match self.os {
            TargetOs::Darwin => "mac",
            _ => "linux",
        }
    }

    fn current_user(&self) -> Result<String, KaizenError> {
        let out = self
            .runtime
            .executor
            .execute(ProcessCommand::run("id", ["-un"]).capturing())?;
        Ok(out.stdout.trim().to_owned())
    }

    fn nix_config_dir(&self) -> Result<std::path::PathBuf, KaizenError> {
        Ok(self.runtime.paths.home_dir()
            .ok_or(KaizenError::HomeDirUnavailable)?
            .join(".config/nix"))
    }

    fn run_darwin_rebuild(&self) -> Result<(), KaizenError> {
        let flake = self.nix_config_dir()?.to_string_lossy().into_owned();
        self.runtime
            .executor
            .execute(ProcessCommand::run("darwin-rebuild", ["switch", "--flake", &flake]).sudo())?;
        Ok(())
    }

    fn run_home_manager(&self) -> Result<(), KaizenError> {
        let user = self.current_user()?;
        let nix_dir = self.nix_config_dir()?;
        let flake = format!("{}#{}@{}", nix_dir.display(), user, self.flake_host());
        self.runtime.executor.execute(ProcessCommand::run(
            "home-manager",
            ["switch", "--flake", &flake, "--impure"],
        ))?;
        Ok(())
    }

    fn run_nix_flake_update(&self, dry_run: bool) -> Result<(), KaizenError> {
        if dry_run {
            return Ok(());
        }
        let nix_dir = self.nix_config_dir()?;
        let flake_str = nix_dir.to_string_lossy().into_owned();
        self.runtime.executor.execute(ProcessCommand::run(
            "nix",
            ["flake", "update", "--flake", &flake_str],
        ))?;
        Ok(())
    }

    fn run_nix_gc(&self, dry_run: bool) -> Result<(), KaizenError> {
        if dry_run {
            return Ok(());
        }
        self.runtime.executor.execute(ProcessCommand::run(
            "nix-collect-garbage",
            ["--delete-older-than", "7d"],
        ))?;
        self.runtime
            .executor
            .execute(ProcessCommand::run("nix-store", ["--optimise"]))?;
        Ok(())
    }

    fn nix_install_steps(&self) -> Vec<String> {
        let mut steps = vec![];
        if self.os == TargetOs::Darwin {
            steps.push("sudo darwin-rebuild switch --flake ~/.config/nix".into());
        }
        let user = self.current_user().unwrap_or_else(|_| "<user>".into());
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

    fn sync(
        &self,
        plan: &WorkflowPlan,
        opts: &crate::SyncOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<crate::SyncReport, KaizenError> {
        let apply = self.apply(plan, opts, reporter)?;
        let install = self.install(plan, opts, reporter)?;
        self.post_apply(opts, reporter)?;
        Ok(crate::SyncReport { install, apply })
    }
}

impl InstallBackend for NixSyncBackend {
    fn install(
        &self,
        _plan: &WorkflowPlan,
        opts: &SyncOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<InstallReport, KaizenError> {
        let steps = self.nix_install_steps();

        if opts.dry_run {
            return Ok(InstallReport {
                steps,
                warnings: vec![],
            });
        }

        if self.os == TargetOs::Darwin {
            reporter.step("→ darwin-rebuild switch");
            self.run_darwin_rebuild()?;
        }
        reporter.step("→ home-manager switch");
        self.run_home_manager()?;

        Ok(InstallReport {
            steps,
            warnings: vec![],
        })
    }
}

impl PostApplyBackend for NixSyncBackend {
    fn post_apply(
        &self,
        opts: &SyncOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<(), KaizenError> {
        if let Some(step) = self.dev_tools.install_step() {
            reporter.step(&format!("→ {}", step.label));
        }
        self.dev_tools.install(opts.dry_run)
    }
}

impl ApplyBackend for NixSyncBackend {
    fn apply(
        &self,
        plan: &WorkflowPlan,
        opts: &SyncOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<ApplyReport, KaizenError> {
        common::chezmoi_write_and_apply(
            &plan.config_plan,
            opts.dry_run,
            reporter,
            self.runtime.chezmoi.as_ref(),
            self.runtime.fs.as_ref(),
        )
    }

    fn apply_preview(&self, _plan: &WorkflowPlan) -> SyncPreview {
        let mut steps = vec![SyncStep {
            label: "apply dotfiles".into(),
            command: "chezmoi apply".into(),
        }];
        if let Some(step) = self.dev_tools.install_step() {
            steps.push(SyncStep {
                label: step.label,
                command: step.command,
            });
        }
        SyncPreview { steps }
    }
}

impl UpdateBackend for NixSyncBackend {
    fn update(
        &self,
        plan: &WorkflowPlan,
        opts: &UpdateOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<UpdateReport, KaizenError> {
        self.run_nix_flake_update(opts.dry_run)?;

        self.sync(
            plan,
            &SyncOpts {
                dry_run: opts.dry_run,
            },
            reporter,
        )?;

        let tools: Vec<String> = plan.install_plan.dev_tools.keys().cloned().collect();
        self.dev_tools.upgrade(&tools, opts.dry_run)?;

        Ok(UpdateReport {
            upgraded: vec!["nix (home-manager switch)".into()],
            warnings: vec![],
        })
    }
}

impl CleanBackend for NixSyncBackend {
    fn clean(&self, opts: &CleanOpts) -> Result<CleanReport, KaizenError> {
        let steps = common::clean_steps(&self.os, true, self.container.as_ref());
        if !opts.dry_run {
            self.run_nix_gc(false)?;
            common::os_cache_clean(&self.os, false, self.runtime.executor.as_ref())?;
            self.container.clean(false)?;
        }
        Ok(common::clean_report_from_steps(steps))
    }
}

impl PreviewBackend for NixSyncBackend {
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

        if let Some(step) = self.dev_tools.install_step() {
            steps.push(SyncStep {
                label: step.label,
                command: step.command,
            });
        }

        let _ = plan;
        SyncPreview { steps }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;
    use crate::{
        container::NoopContainerCleaner,
        executor::NoopExecutor,
        plan::{ConfigPlan, HookPlan, InstallPlan},
        progress::NoopReporter,
        runtime::Runtime,
        sync_backend::SyncOpts,
        toolchain::NoopDevTools,
        UserSettings,
    };
    use indexmap::IndexMap;

    fn mock_backend(os: TargetOs) -> NixSyncBackend {
        NixSyncBackend::new(
            os,
            Runtime::new(
                Arc::new(NoopExecutor),
                Arc::new(crate::StdFileSystem),
                Arc::new(crate::NoopChezmoiClient),
                Arc::new(crate::StdPathProvider),
            ),
            Box::new(NoopDevTools),
            Box::new(NoopContainerCleaner),
        )
    }

    fn empty_plan(os: TargetOs) -> WorkflowPlan {
        WorkflowPlan::new(
            os,
            vec![],
            InstallPlan {
                programs: vec![],
                dev_tools: IndexMap::new(),
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
        assert_eq!(mock_backend(TargetOs::Darwin).flake_host(), "mac");
    }

    #[test]
    fn flake_host_is_linux_on_fedora() {
        assert_eq!(mock_backend(TargetOs::Fedora).flake_host(), "linux");
    }

    #[test]
    fn flake_host_is_linux_on_ubuntu() {
        assert_eq!(mock_backend(TargetOs::Ubuntu).flake_host(), "linux");
    }

    #[test]
    fn install_dry_run_returns_steps_without_spawning() {
        let backend = mock_backend(TargetOs::Darwin);
        let plan = empty_plan(TargetOs::Darwin);
        let report = backend
            .install(&plan, &SyncOpts { dry_run: true }, &NoopReporter)
            .unwrap();
        assert!(!report.steps.is_empty());
    }

    #[test]
    fn install_dry_run_darwin_steps_include_darwin_rebuild() {
        let backend = mock_backend(TargetOs::Darwin);
        let plan = empty_plan(TargetOs::Darwin);
        let report = backend
            .install(&plan, &SyncOpts { dry_run: true }, &NoopReporter)
            .unwrap();
        assert!(
            report.steps.iter().any(|s| s.contains("darwin-rebuild")),
            "darwin steps must include darwin-rebuild, got: {report:?}"
        );
    }

    #[test]
    fn install_dry_run_linux_steps_skip_darwin_rebuild() {
        let backend = mock_backend(TargetOs::Linux);
        let plan = empty_plan(TargetOs::Linux);
        let report = backend
            .install(&plan, &SyncOpts { dry_run: true }, &NoopReporter)
            .unwrap();
        assert!(
            report.steps.iter().all(|s| !s.contains("darwin-rebuild")),
            "linux steps must not include darwin-rebuild"
        );
    }

    #[test]
    fn apply_preview_contains_chezmoi_apply() {
        let backend = mock_backend(TargetOs::Darwin);
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
        let backend = mock_backend(TargetOs::Darwin);
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
        let backend = mock_backend(TargetOs::Darwin);
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
