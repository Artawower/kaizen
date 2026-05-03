use std::path::Path;

use anyhow::Result;
use kaizen_core::{Installer, KaizenEngine, KaizenError, TargetOs, UptInstaller};
use owo_colors::OwoColorize;

use crate::{ensure, output};

pub fn run(engine: &KaizenEngine, config_path: &Path, dry_run: bool) -> Result<()> {
    output::page_header(if dry_run {
        "install  (dry-run)"
    } else {
        "install"
    });
    ensure::require(&[&ensure::UPT])?;
    run_with(
        engine,
        config_path,
        dry_run,
        TargetOs::detect(),
        &UptInstaller,
    )
}

fn run_with(
    engine: &KaizenEngine,
    config_path: &Path,
    dry_run: bool,
    target_os: TargetOs,
    installer: &dyn Installer,
) -> Result<()> {
    let config = engine.load_config(config_path)?;
    output::warn_if_schema_outdated(&config);
    let plan = engine.build_workflow_plan(&config, target_os)?;

    if plan.install_plan.programs.is_empty() {
        output::item_warn("no programs to install — check your config and features dir");
        return Ok(());
    }

    print_programs(&plan.install_plan.programs);
    execute_install(&plan.install_plan.programs, dry_run, installer)
}

fn execute_install(programs: &[String], dry_run: bool, installer: &dyn Installer) -> Result<()> {
    let preview = installer.preview_install(programs);
    println!();

    if dry_run {
        println!("  {}  {}", "→".dimmed(), preview.dimmed());
        println!();
        println!("  Run without --dry-run to apply.");
        return Ok(());
    }

    println!("  {}  {}", "→".bold(), preview);
    println!();
    match installer.install(programs) {
        Ok(()) => {
            output::item_ok(&format!("{} package(s) installed", programs.len()));
        }
        Err(KaizenError::InstallerPartialFailure { failed, .. }) => {
            let ok = programs.len() - failed.len();
            if ok > 0 {
                output::item_ok(&format!("{ok} package(s) installed"));
            }
            for pkg in &failed {
                output::item_warn(&format!(
                    "{pkg}: failed — check for conflicts or update the feature file"
                ));
            }
        }
        Err(e) => return Err(e.into()),
    }
    Ok(())
}

fn print_programs(programs: &[String]) {
    output::header(&format!("Programs ({})", programs.len()));
    for chunk in programs.chunks(4) {
        let row: Vec<String> = chunk.iter().map(|p| format!("{p:<20}")).collect();
        println!("  {}", row.join(""));
    }
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::path::PathBuf;

    use kaizen_core::KaizenError;

    use super::*;

    struct RecordingInstaller {
        calls: RefCell<Vec<Vec<String>>>,
    }

    impl RecordingInstaller {
        fn new() -> Self {
            Self {
                calls: RefCell::new(vec![]),
            }
        }

        fn was_called(&self) -> bool {
            !self.calls.borrow().is_empty()
        }

        fn last_call(&self) -> Option<Vec<String>> {
            self.calls.borrow().last().cloned()
        }
    }

    impl Installer for RecordingInstaller {
        fn install(&self, programs: &[String]) -> Result<(), KaizenError> {
            self.calls.borrow_mut().push(programs.to_vec());
            Ok(())
        }

        fn preview_install(&self, programs: &[String]) -> String {
            format!("mock install {}", programs.join(" "))
        }
    }

    fn fixture_path(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name)
    }

    fn fixture_engine() -> KaizenEngine {
        KaizenEngine::new(fixture_path("features"))
    }

    #[test]
    fn dry_run_does_not_call_installer() {
        let recorder = RecordingInstaller::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            true,
            TargetOs::Darwin,
            &recorder,
        )
        .unwrap();
        assert!(!recorder.was_called());
    }

    #[test]
    fn normal_mode_calls_installer() {
        let recorder = RecordingInstaller::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            false,
            TargetOs::Darwin,
            &recorder,
        )
        .unwrap();
        assert!(recorder.was_called());
    }

    #[test]
    fn passes_resolved_programs_to_installer() {
        let recorder = RecordingInstaller::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            false,
            TargetOs::Darwin,
            &recorder,
        )
        .unwrap();
        let programs = recorder.last_call().unwrap();
        assert!(programs.contains(&"git".to_owned()));
        assert!(programs.contains(&"ripgrep".to_owned()));
    }

    #[test]
    fn fedora_applies_package_overrides() {
        let recorder = RecordingInstaller::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            false,
            TargetOs::Fedora,
            &recorder,
        )
        .unwrap();
        let programs = recorder.last_call().unwrap();
        assert!(
            programs.contains(&"fd-find".to_owned()),
            "expected fd-find override, got {programs:?}"
        );
        assert!(
            !programs.contains(&"fd".to_owned()),
            "canonical 'fd' should be replaced"
        );
    }
}
