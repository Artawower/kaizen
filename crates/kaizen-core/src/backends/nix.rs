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
        Ok(self
            .runtime
            .paths
            .home_dir()
            .ok_or(KaizenError::HomeDirUnavailable)?
            .join(".config/nix"))
    }

    /// Nix profile directories to prepend to PATH for all nix subprocesses.
    ///
    /// `home-manager`, `darwin-rebuild` and other tools call `nix` internally.
    /// Without these prefixes they fail when Nix is not yet on the shell PATH.
    fn nix_path_prefix(&self) -> Vec<String> {
        let mut dirs = vec![
            "/nix/var/nix/profiles/default/bin".to_owned(),
            // nix-darwin system sw path — darwin-rebuild lives here after first activation
            "/run/current-system/sw/bin".to_owned(),
        ];
        if let Some(home) = self.runtime.paths.home_dir() {
            dirs.push(home.join(".nix-profile/bin").to_string_lossy().into_owned());
            dirs.push(
                home.join(".local/state/nix/profile/bin")
                    .to_string_lossy()
                    .into_owned(),
            );
        }
        dirs
    }

    fn darwin_rebuild_available(&self) -> bool {
        self.nix_path_prefix()
            .iter()
            .any(|dir| std::path::Path::new(dir).join("darwin-rebuild").exists())
            || self.runtime.paths.is_tool_available("darwin-rebuild")
    }

    fn run_darwin_rebuild(&self) -> Result<(), KaizenError> {
        let flake = self.nix_config_dir()?.to_string_lossy().into_owned();
        let cmd = if self.darwin_rebuild_available() {
            ProcessCommand::run("darwin-rebuild", ["switch", "--flake", &flake, "--impure"])
                .sudo()
                .with_path_prefix(self.nix_path_prefix())
        } else {
            // nix-darwin not yet bootstrapped — use `nix run` to perform the first switch.
            // After this completes, darwin-rebuild will be available for subsequent runs.
            ProcessCommand::run(
                "nix",
                [
                    "run",
                    "github:LnL7/nix-darwin/master#darwin-rebuild",
                    "--",
                    "switch",
                    "--flake",
                    &flake,
                    "--impure",
                ],
            )
            .sudo()
            .with_path_prefix(self.nix_path_prefix())
        };
        self.runtime.executor.execute(cmd)?;
        Ok(())
    }

    fn run_home_manager(&self) -> Result<(), KaizenError> {
        let user = self.current_user()?;
        let nix_dir = self.nix_config_dir()?;
        let flake = format!("{}#{}@{}", nix_dir.display(), user, self.flake_host());

        // Prefer the installed home-manager binary; fall back to `nix run`
        // on a fresh system where home-manager is not yet in PATH.
        let hm_in_path = self
            .runtime
            .executor
            .execute(
                ProcessCommand::run("home-manager", ["--version"])
                    .capturing()
                    .with_path_prefix(self.nix_path_prefix()),
            )
            .is_ok();

        let (cmd, args): (&str, Vec<&str>) = if hm_in_path {
            (
                "home-manager",
                vec!["switch", "--flake", &flake, "--impure"],
            )
        } else {
            (
                "nix",
                vec![
                    "run",
                    "nixpkgs#home-manager",
                    "--",
                    "switch",
                    "--flake",
                    &flake,
                    "--impure",
                ],
            )
        };

        self.runtime
            .executor
            .execute(ProcessCommand::run(cmd, args).with_path_prefix(self.nix_path_prefix()))?;
        Ok(())
    }

    fn run_nix_flake_update(&self, dry_run: bool) -> Result<(), KaizenError> {
        if dry_run {
            return Ok(());
        }
        let nix_dir = self.nix_config_dir()?;
        let flake_str = nix_dir.to_string_lossy().into_owned();
        self.runtime.executor.execute(
            ProcessCommand::run("nix", ["flake", "update", "--flake", &flake_str])
                .with_path_prefix(self.nix_path_prefix()),
        )?;
        Ok(())
    }

    fn run_nix_gc(&self, dry_run: bool) -> Result<(), KaizenError> {
        if dry_run {
            return Ok(());
        }
        self.runtime.executor.execute(
            ProcessCommand::run("nix-collect-garbage", ["--delete-older-than", "7d"])
                .with_path_prefix(self.nix_path_prefix()),
        )?;
        self.runtime.executor.execute(
            ProcessCommand::run("nix-store", ["--optimise"])
                .with_path_prefix(self.nix_path_prefix()),
        )?;
        Ok(())
    }

    /// Prepare source formulas before darwin-rebuild:
    ///
    /// 1. Unlink any OTHER installed versions of the same formula family
    ///    (e.g. emacs-plus@31 when switching to emacs-plus@30).
    /// 2. Remove root-owned .app bundles from /Applications that bottles place
    ///    as root and that block `brew reinstall` from updating them.
    /// 3. Force-link with --overwrite so brew bundle install skips already-linked
    ///    formulae instead of failing on non-symlink file conflicts.
    ///
    /// All steps are non-fatal: formula may not be installed on a fresh system.
    fn prelink_brew_source_formulas(&self, formulas: &[String]) {
        for formula in formulas {
            self.unlink_other_versions(formula);
            self.remove_root_app_bundles(formula);
            let _ = self.runtime.executor.execute(ProcessCommand::run(
                "brew",
                ["link", "--overwrite", formula.as_str()],
            ));
        }
    }

    /// Resolve the Homebrew Cellar path by asking brew directly.
    ///
    /// Avoids the `/opt/homebrew/Cellar` hardcode that breaks on Intel Macs
    /// and custom Homebrew prefixes (e.g. `/usr/local`).
    fn brew_cellar_dir(&self) -> Option<std::path::PathBuf> {
        let out = self
            .runtime
            .executor
            .execute(ProcessCommand::run("brew", ["--cellar"]).capturing())
            .ok()?;
        let path = out.stdout.trim();
        if path.is_empty() {
            return None;
        }
        Some(std::path::PathBuf::from(path))
    }

    /// Unlink all Cellar kegs that share the same base name but differ in version.
    ///
    /// e.g. target = "d12frosted/emacs-plus/emacs-plus@30"
    ///      base   = "emacs-plus"
    ///      unlinks "emacs-plus@31", "emacs-plus@29", … but not "emacs-plus@30".
    ///
    /// The match uses `== base` (unversioned) or `starts_with("{base}@")` to
    /// avoid false-positives such as "emacs-plus-native" matching "emacs-plus".
    fn unlink_other_versions(&self, formula: &str) {
        let keg_name = formula.rsplit('/').next().unwrap_or(formula);
        let base = keg_name.split('@').next().unwrap_or(keg_name);
        let versioned_prefix = format!("{base}@");

        let Some(cellar) = self.brew_cellar_dir() else {
            return;
        };
        let Ok(entries) = std::fs::read_dir(&cellar) else {
            return;
        };
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            let is_same_family =
                name_str == base || name_str.starts_with(versioned_prefix.as_str());
            if is_same_family && name_str != keg_name {
                let _ = self
                    .runtime
                    .executor
                    .execute(ProcessCommand::run("brew", ["unlink", name_str.as_ref()]));
            }
        }
    }

    /// Remove /Applications/<Name>.app if it is owned by root.
    ///
    /// Homebrew bottles install app bundles to /Applications as root, which
    /// blocks subsequent `brew reinstall --build-from-source` from updating them.
    /// We discover the bundle path by asking brew where it installed the app.
    fn remove_root_app_bundles(&self, formula: &str) {
        let Ok(out) = self
            .runtime
            .executor
            .execute(ProcessCommand::run("brew", ["--prefix", formula]).capturing())
        else {
            return;
        };
        let prefix = std::path::Path::new(out.stdout.trim());
        // emacs-plus and similar formulae place Emacs.app next to bin/ in prefix
        let Ok(entries) = std::fs::read_dir(prefix) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("app") {
                continue;
            }
            let app_name = match path.file_name().and_then(|n| n.to_str()) {
                Some(n) => n.to_owned(),
                None => continue,
            };
            let system_app = std::path::Path::new("/Applications").join(&app_name);
            let owned_by_root = system_app
                .symlink_metadata()
                .ok()
                .map(|m| {
                    use std::os::unix::fs::MetadataExt;
                    m.uid() == 0
                })
                .unwrap_or(false);
            if owned_by_root {
                let _ = self.runtime.executor.execute(
                    ProcessCommand::run("rm", ["-rf", system_app.to_string_lossy().as_ref()])
                        .sudo(),
                );
            }
        }
    }

    /// Check if a formula has missing (broken) dylib paths.
    ///
    /// Uses `brew linkage` without `--test` and looks for "Missing:" lines.
    /// `--test` exits non-zero for indirect dependencies too, giving false
    /// positives on formulae like emacs-plus that use many transitive libs.
    ///
    /// Only the keg name (last path component) is passed to `brew linkage` —
    /// the full tap path (e.g. "d12frosted/emacs-plus/emacs-plus@31") is only
    /// needed for `brew install`; `brew linkage` operates on installed kegs.
    ///
    /// Returns `Err` if `brew linkage` itself fails to run (treat as suspect).
    fn brew_linkage_broken(&self, formula: &str) -> Result<bool, KaizenError> {
        let keg_name = formula.rsplit('/').next().unwrap_or(formula);
        let out = self
            .runtime
            .executor
            .execute(ProcessCommand::run("brew", ["linkage", keg_name]).capturing())?;
        // brew uses different section headers across versions:
        //   "Missing libraries:", "Missing:", "Broken dependencies:"
        Ok(out.stdout.lines().any(|l| {
            let t = l.trim_start();
            t.starts_with("Missing") || t.starts_with("Broken dependencies")
        }))
    }

    /// For each formula in `brew_source_formulas`, check for missing dylibs.
    /// If broken, reinstall from source so it links against current library versions.
    ///
    /// If `brew linkage` itself fails to run, the formula is treated as suspect
    /// and a repair is attempted rather than silently skipped.
    fn repair_brew_source_formulas(
        &self,
        formulas: &[String],
        reporter: &dyn ProgressReporter,
    ) -> Result<(), KaizenError> {
        for formula in formulas {
            match self.brew_linkage_broken(formula) {
                Ok(false) => continue,
                Ok(true) => {
                    reporter.step(&format!(
                        "→ {formula}: broken dylibs detected — rebuilding from source"
                    ));
                }
                Err(e) => {
                    reporter.step(&format!(
                        "→ {formula}: brew linkage check failed ({e}) — attempting repair"
                    ));
                }
            }

            // Ignore exit code: brew reinstall may exit non-zero if a registered
            // launchd service fails to restart under sudo (Input/output error).
            let _ = self.runtime.executor.execute(ProcessCommand::run(
                "brew",
                ["reinstall", "--build-from-source", formula.as_str()],
            ));

            // Force-relink after source build: brew reinstall may leave
            // app bundles pointing to the old keg if auto-link failed mid-way.
            let _ = self.runtime.executor.execute(ProcessCommand::run(
                "brew",
                ["link", "--overwrite", formula.as_str()],
            ));

            // Re-sign .app bundles after source build.
            // macOS 15.x refuses to open unsigned binaries built from source
            // with error -600 (procNotFound). xattr -cr strips disallowed
            // attributes first, then codesign applies an ad-hoc signature.
            self.codesign_brew_app_bundles(formula, reporter);

            if self.brew_linkage_broken(formula).unwrap_or(true) {
                return Err(KaizenError::CommandFailed {
                    cmd: format!("brew reinstall --build-from-source {formula}"),
                    code: Some(1),
                });
            }
        }
        Ok(())
    }

    /// Re-sign all `.app` bundles in a formula's prefix with an ad-hoc signature.
    ///
    /// macOS 15.x refuses to open source-built binaries via LaunchServices
    /// (error -600) unless they carry a valid code signature. The formula's
    /// post-install hook should do this, but a `brew reinstall --build-from-source`
    /// may skip it. We strip disallowed xattrs first (`xattr -cr`) then apply
    /// an ad-hoc signature (`codesign --force --deep --sign -`).
    fn codesign_brew_app_bundles(&self, formula: &str, reporter: &dyn ProgressReporter) {
        let Ok(out) = self
            .runtime
            .executor
            .execute(ProcessCommand::run("brew", ["--prefix", formula]).capturing())
        else {
            return;
        };
        let prefix = std::path::PathBuf::from(out.stdout.trim());
        let Ok(entries) = std::fs::read_dir(&prefix) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("app") {
                continue;
            }
            let path_str = path.to_string_lossy().into_owned();
            reporter.step(&format!("→ codesign {path_str}"));
            let _ = self
                .runtime
                .executor
                .execute(ProcessCommand::run("xattr", ["-cr", &path_str]));
            let _ = self.runtime.executor.execute(ProcessCommand::run(
                "codesign",
                ["--force", "--deep", "--sign", "-", &path_str],
            ));
        }
    }

    /// For each formula, symlink any `.app` bundles from its brew prefix into
    /// `/Applications`, replacing whatever was there before.
    ///
    /// Uses `brew --prefix formula` so the path is correct on any Homebrew
    /// installation (Apple Silicon `/opt/homebrew`, Intel `/usr/local`, etc.).
    /// Non-fatal: missing prefix or absent `.app` bundles are silently skipped.
    fn link_brew_app_bundles(&self, formulas: &[String], reporter: &dyn ProgressReporter) {
        for formula in formulas {
            let Ok(out) = self
                .runtime
                .executor
                .execute(ProcessCommand::run("brew", ["--prefix", formula.as_str()]).capturing())
            else {
                continue;
            };
            let prefix = std::path::PathBuf::from(out.stdout.trim());
            let Ok(entries) = std::fs::read_dir(&prefix) else {
                continue;
            };
            for entry in entries.flatten() {
                let src = entry.path();
                if src.extension().and_then(|e| e.to_str()) != Some("app") {
                    continue;
                }
                let Some(name) = src.file_name() else {
                    continue;
                };
                let dest = std::path::Path::new("/Applications").join(name);
                // Remove stale entry (hardcopy or wrong-target symlink) before re-linking.
                let _ = std::fs::remove_file(&dest);
                let _ = std::fs::remove_dir_all(&dest);
                if std::os::unix::fs::symlink(&src, &dest).is_ok() {
                    reporter.step(&format!("→ linked {}", dest.display()));
                }
            }
        }
    }

    /// Start the Homebrew-managed LaunchAgent for each formula that ships one.
    ///
    /// `brew services start` is idempotent — it is safe to call even if the
    /// service is already running. Runs without `sudo` so the service is
    /// registered as a user LaunchAgent (`~/Library/LaunchAgents/`), not a
    /// system daemon.
    fn start_brew_services(&self, formulas: &[String], reporter: &dyn ProgressReporter) {
        for formula in formulas {
            // Use the keg name (last path component) for brew services.
            let keg_name = formula.rsplit('/').next().unwrap_or(formula.as_str());
            // Check whether this formula actually ships a service plist before
            // printing progress, to avoid noise for formulas without daemons.
            let has_service = self
                .runtime
                .executor
                .execute(
                    ProcessCommand::run("brew", ["services", "info", keg_name, "--json"])
                        .capturing(),
                )
                .ok()
                .map(|o| o.stdout.contains("\"running\"") || o.stdout.contains("\"stopped\""))
                .unwrap_or(false);

            if !has_service {
                continue;
            }

            reporter.step(&format!("→ brew services start {keg_name}"));
            let _ = self
                .runtime
                .executor
                .execute(ProcessCommand::run("brew", ["services", "start", keg_name]));
        }
    }

    fn nix_install_steps(&self) -> Vec<String> {
        let mut steps = vec![];
        if self.os == TargetOs::Darwin {
            let cmd = if self.darwin_rebuild_available() {
                "sudo darwin-rebuild switch --flake ~/.config/nix --impure".into()
            } else {
                "sudo nix run github:LnL7/nix-darwin/master#darwin-rebuild -- switch --flake ~/.config/nix --impure".into()
            };
            steps.push(cmd);
        }
        let user = self.current_user().unwrap_or_else(|_| "<user>".into());
        let nix_dir = self
            .nix_config_dir()
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_else(|_| "~/.config/nix".into());
        steps.push(format!(
            "home-manager switch --flake {}#{}@{} --impure",
            nix_dir,
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
        plan: &WorkflowPlan,
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
            // Unlink source formulas before darwin-rebuild so brew bundle can
            // relink cleanly without "already exists" symlink conflicts from
            // previous installations (e.g. share/info/emacs/dir).
            self.prelink_brew_source_formulas(&plan.install_plan.brew_source_formulas);
            reporter.step("→ darwin-rebuild switch");
            self.run_darwin_rebuild()?;
            self.repair_brew_source_formulas(&plan.install_plan.brew_source_formulas, reporter)?;
            self.link_brew_app_bundles(&plan.install_plan.brew_source_formulas, reporter);
            self.start_brew_services(&plan.install_plan.brew_source_formulas, reporter);
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
                ..Default::default()
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
        let steps = common::clean_steps(&self.runtime.pm, true, self.container.as_ref());
        if !opts.dry_run {
            self.run_nix_gc(false)?;
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
        fs::mem::MemFileSystem,
        paths::test::TestPathProvider,
        plan::{ConfigPlan, HookPlan, InstallPlan},
        progress::NoopReporter,
        runtime::Runtime,
        sync_backend::SyncOpts,
        toolchain::NoopDevTools,
        UserSettings,
    };
    use indexmap::IndexMap;

    fn mock_backend(os: TargetOs) -> NixSyncBackend {
        let pm = os.package_manager_kind();
        NixSyncBackend::new(
            os,
            Runtime::new(
                Arc::new(NoopExecutor),
                Arc::new(MemFileSystem::new()),
                Arc::new(crate::NoopChezmoiClient),
                Arc::new(TestPathProvider::default()),
                pm,
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
                brew_source_formulas: vec![],
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
    }

    #[test]
    fn install_dry_run_darwin_steps_include_darwin_rebuild() {
        let backend = mock_backend(TargetOs::Darwin);
        let plan = empty_plan(TargetOs::Darwin);
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
            .install(
                &plan,
                &SyncOpts {
                    dry_run: true,
                    ..Default::default()
                },
                &NoopReporter,
            )
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
