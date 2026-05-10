use crate::{
    backends::common,
    container::ContainerCleaner,
    installer::PackageInstaller,
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

pub struct UptSyncBackend {
    runtime: Runtime,
    installer: Box<dyn PackageInstaller>,
    dev_tools: Box<dyn DevToolsManager>,
    container: Box<dyn ContainerCleaner>,
}

impl UptSyncBackend {
    pub fn new(
        _os: TargetOs,
        runtime: Runtime,
        installer: Box<dyn PackageInstaller>,
        dev_tools: Box<dyn DevToolsManager>,
        container: Box<dyn ContainerCleaner>,
    ) -> Self {
        Self {
            runtime,
            installer,
            dev_tools,
            container,
        }
    }
}

impl SyncBackend for UptSyncBackend {
    fn id(&self) -> &'static str {
        "upt"
    }
}

impl InstallBackend for UptSyncBackend {
    fn install(
        &self,
        plan: &WorkflowPlan,
        opts: &SyncOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<InstallReport, KaizenError> {
        let programs = &plan.install_plan.programs;
        if programs.is_empty() {
            return Ok(InstallReport::default());
        }

        if opts.dry_run {
            return Ok(InstallReport {
                steps: vec![self.installer.preview_install(programs)],
                warnings: vec![],
            });
        }

        reporter.step("→ upt install");
        self.installer.install(programs)?;
        Ok(InstallReport {
            steps: vec![self.installer.preview_install(programs)],
            warnings: vec![],
        })
    }
}

impl PostApplyBackend for UptSyncBackend {
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

impl ApplyBackend for UptSyncBackend {
    fn apply(
        &self,
        plan: &WorkflowPlan,
        opts: &SyncOpts,
        reporter: &dyn ProgressReporter,
    ) -> Result<ApplyReport, KaizenError> {
        common::chezmoi_write_and_apply(
            &plan.config_plan,
            opts.dry_run,
            opts.force,
            reporter,
            self.runtime.chezmoi.as_ref(),
            self.runtime.fs.as_ref(),
            self.runtime.paths.as_ref(),
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

impl UpdateBackend for UptSyncBackend {
    fn update(
        &self,
        plan: &WorkflowPlan,
        opts: &UpdateOpts,
        _reporter: &dyn ProgressReporter,
    ) -> Result<UpdateReport, KaizenError> {
        let programs = &plan.install_plan.programs;
        let mut warnings = vec![];

        if !programs.is_empty() {
            if opts.dry_run {
                return Ok(UpdateReport {
                    upgraded: programs.clone(),
                    warnings,
                });
            }
            match self.installer.upgrade(programs) {
                Ok(()) => {}
                Err(KaizenError::InstallerPartialFailure { failed, .. }) => {
                    warnings.extend(failed.iter().map(|p| format!("{p}: failed to upgrade")));
                }
                Err(e) => return Err(e),
            }
        }

        let tools: Vec<String> = plan.install_plan.dev_tools.keys().cloned().collect();
        self.dev_tools.upgrade(&tools, opts.dry_run)?;

        Ok(UpdateReport {
            upgraded: programs.clone(),
            warnings,
        })
    }
}

impl CleanBackend for UptSyncBackend {
    fn clean(&self, opts: &CleanOpts) -> Result<CleanReport, KaizenError> {
        let steps = common::clean_steps(&self.runtime.pm, false, self.container.as_ref());
        if !opts.dry_run {
            common::os_cache_clean(
                &self.runtime.pm,
                false,
                self.runtime.executor.as_ref(),
                self.runtime.paths.as_ref(),
            )?;
            self.container.clean(false)?;
        }
        Ok(common::clean_report_from_steps(steps))
    }
}

impl PreviewBackend for UptSyncBackend {
    fn preview(&self, plan: &WorkflowPlan) -> SyncPreview {
        let mut steps = vec![];

        if !plan.install_plan.programs.is_empty() {
            steps.push(SyncStep {
                label: "install packages".into(),
                command: self.installer.preview_install(&plan.install_plan.programs),
            });
        }

        steps.push(SyncStep {
            label: "apply dotfiles".into(),
            command: "chezmoi apply".into(),
        });

        if let Some(step) = self.dev_tools.install_step() {
            steps.push(SyncStep {
                label: step.label,
                command: step.command,
            });
        }

        SyncPreview { steps }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        chezmoi_client::NoopChezmoiClient,
        container::NoopContainerCleaner,
        executor::NoopExecutor,
        fs::mem::MemFileSystem,
        installer::{Installer, Updater},
        paths::test::TestPathProvider,
        plan::{ConfigPlan, HookPlan, InstallPlan},
        progress::NoopReporter,
        runtime::Runtime,
        sync_backend::{CleanOpts, SyncOpts, UpdateOpts},
        toolchain::NoopDevTools,
        UserSettings,
    };
    use indexmap::IndexMap;

    struct MockInstaller;

    impl Installer for MockInstaller {
        fn install(&self, _programs: &[String]) -> Result<(), KaizenError> {
            Ok(())
        }
        fn preview_install(&self, programs: &[String]) -> String {
            format!("mock install {}", programs.join(" "))
        }
    }

    impl Updater for MockInstaller {
        fn upgrade(&self, _programs: &[String]) -> Result<(), KaizenError> {
            Ok(())
        }
        fn preview_upgrade(&self, programs: &[String]) -> String {
            format!("mock upgrade {}", programs.join(" "))
        }
    }

    fn mock_backend(os: TargetOs) -> UptSyncBackend {
        let pm = os.package_manager_kind();
        UptSyncBackend::new(
            os,
            Runtime::new(
                std::sync::Arc::new(NoopExecutor),
                std::sync::Arc::new(MemFileSystem::new()),
                std::sync::Arc::new(NoopChezmoiClient),
                std::sync::Arc::new(TestPathProvider::default()),
                pm,
            ),
            Box::new(MockInstaller),
            Box::new(NoopDevTools),
            Box::new(NoopContainerCleaner),
        )
    }

    fn empty_plan() -> WorkflowPlan {
        WorkflowPlan::new(
            TargetOs::Darwin,
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

    fn plan_with_programs(programs: &[&str]) -> WorkflowPlan {
        let mut p = empty_plan();
        p.install_plan.programs = programs.iter().map(|s| s.to_string()).collect();
        p
    }

    #[test]
    fn install_dry_run_returns_steps_without_calling_upt() {
        let backend = mock_backend(TargetOs::Darwin);
        let plan = plan_with_programs(&["git", "ripgrep"]);
        let report = backend
            .install(
                &plan,
                &SyncOpts {
                    dry_run: true,
                    ..Default::default()
                },
                &NoopReporter,
            )
            .unwrap();
        assert!(!report.steps.is_empty());
        assert!(report.steps[0].contains("git"));
    }

    #[test]
    fn install_empty_programs_returns_empty_report() {
        let backend = mock_backend(TargetOs::Darwin);
        let plan = empty_plan();
        let report = backend
            .install(
                &plan,
                &SyncOpts {
                    dry_run: true,
                    ..Default::default()
                },
                &NoopReporter,
            )
            .unwrap();
        assert!(report.steps.is_empty());
    }

    #[test]
    fn update_dry_run_returns_programs_without_spawning() {
        let backend = mock_backend(TargetOs::Darwin);
        let plan = plan_with_programs(&["git"]);
        let report = backend
            .update(
                &plan,
                &UpdateOpts {
                    dry_run: true,
                    update_flake: false,
                },
                &NoopReporter,
            )
            .unwrap();
        assert!(report.upgraded.contains(&"git".to_owned()));
    }

    #[test]
    fn apply_preview_contains_chezmoi() {
        let backend = mock_backend(TargetOs::Darwin);
        let plan = empty_plan();
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
    fn apply_preview_does_not_contain_upt() {
        let backend = mock_backend(TargetOs::Darwin);
        let plan = plan_with_programs(&["git"]);
        let preview = backend.apply_preview(&plan);
        assert!(
            preview.steps.iter().all(|s| !s.command.contains("upt")),
            "apply_preview must not include upt install"
        );
    }

    #[test]
    fn clean_dry_run_returns_brew_step_on_darwin() {
        let backend = mock_backend(TargetOs::Darwin);
        let report = backend.clean(&CleanOpts { dry_run: true }).unwrap();
        assert!(
            report.steps.iter().any(|s| s.contains("brew")),
            "darwin clean steps must include brew cleanup, got: {:?}",
            report.steps
        );
    }

    #[test]
    fn clean_dry_run_returns_dnf_step_on_fedora() {
        let backend = mock_backend(TargetOs::Fedora);
        let report = backend.clean(&CleanOpts { dry_run: true }).unwrap();
        assert!(
            report.steps.iter().any(|s| s.contains("dnf")),
            "fedora clean steps must include dnf clean, got: {:?}",
            report.steps
        );
    }
}
