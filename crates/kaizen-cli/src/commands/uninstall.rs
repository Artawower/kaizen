use std::path::Path;

use anyhow::Result;
use kaizen_core::{KaizenEngine, KaizenError, Remover, TargetOs, UptInstaller};
use owo_colors::OwoColorize;

use crate::{ensure, output, selector};

pub fn run(engine: &KaizenEngine, config_path: &Path, dry_run: bool) -> Result<()> {
    output::page_header(if dry_run {
        "uninstall  (dry-run)"
    } else {
        "uninstall"
    });
    run_with(
        engine,
        config_path,
        dry_run,
        TargetOs::detect(),
        |items| selector::multi_select("Select programs to remove", items),
        &UptInstaller,
    )
}

fn run_with(
    engine: &KaizenEngine,
    config_path: &Path,
    dry_run: bool,
    target_os: TargetOs,
    choose: impl FnOnce(Vec<selector::Item>) -> Result<Option<Vec<String>>>,
    remover: &dyn Remover,
) -> Result<()> {
    let config = engine.load_config(config_path)?;
    output::warn_if_schema_outdated(&config);
    let plan = engine.build_workflow_plan(&config, target_os)?;

    if plan.install_plan.programs.is_empty() {
        output::item_warn("no programs found — check your config and features dir");
        return Ok(());
    }

    let items: Vec<selector::Item> = plan
        .install_plan
        .programs
        .iter()
        .map(|p| selector::Item {
            name: p.clone(),
            desc: None,
            selected: false,
        })
        .collect();

    let Some(chosen) = choose(items)? else {
        return Ok(());
    };

    if chosen.is_empty() {
        output::item_warn("nothing selected — nothing to remove");
        return Ok(());
    }

    if !dry_run {
        ensure::require(&[&ensure::UPT])?;
    }

    execute_remove(&chosen, dry_run, remover)
}

fn execute_remove(programs: &[String], dry_run: bool, remover: &dyn Remover) -> Result<()> {
    let preview = remover.preview_remove(programs);
    println!();

    if dry_run {
        println!("  {}  {}", "→".dimmed(), preview.dimmed());
        println!();
        println!("  Run without --dry-run to apply.");
        return Ok(());
    }

    println!("  {}  {}", "→".bold(), preview);
    println!();
    match remover.remove(programs) {
        Ok(()) => {
            output::item_ok(&format!("{} package(s) removed", programs.len()));
        }
        Err(KaizenError::InstallerPartialFailure { failed, .. }) => {
            let ok = programs.len() - failed.len();
            if ok > 0 {
                output::item_ok(&format!("{ok} package(s) removed"));
            }
            for pkg in &failed {
                output::item_warn(&format!("{pkg}: failed — may not be managed by upt"));
            }
        }
        Err(e) => return Err(e.into()),
    }
    output::item_warn("config unchanged — run kaizen install to re-apply declared packages");
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::path::PathBuf;

    use kaizen_core::KaizenError;

    use super::*;

    struct RecordingRemover {
        calls: RefCell<Vec<Vec<String>>>,
    }

    impl RecordingRemover {
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

    impl Remover for RecordingRemover {
        fn remove(&self, programs: &[String]) -> Result<(), KaizenError> {
            self.calls.borrow_mut().push(programs.to_vec());
            Ok(())
        }

        fn preview_remove(&self, programs: &[String]) -> String {
            format!("mock remove {}", programs.join(" "))
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

    fn choose_all(items: Vec<selector::Item>) -> Result<Option<Vec<String>>> {
        Ok(Some(items.into_iter().map(|i| i.name).collect()))
    }

    fn choose_cancel(_items: Vec<selector::Item>) -> Result<Option<Vec<String>>> {
        Ok(None)
    }

    fn choose_none(_items: Vec<selector::Item>) -> Result<Option<Vec<String>>> {
        Ok(Some(vec![]))
    }

    fn choose_first(items: Vec<selector::Item>) -> Result<Option<Vec<String>>> {
        Ok(items.into_iter().next().map(|i| vec![i.name]))
    }

    #[test]
    fn cancel_does_not_call_remover() {
        let remover = RecordingRemover::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            false,
            TargetOs::Darwin,
            choose_cancel,
            &remover,
        )
        .unwrap();
        assert!(!remover.was_called());
    }

    #[test]
    fn empty_selection_does_not_call_remover() {
        let remover = RecordingRemover::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            false,
            TargetOs::Darwin,
            choose_none,
            &remover,
        )
        .unwrap();
        assert!(!remover.was_called());
    }

    #[test]
    fn dry_run_does_not_call_remover() {
        let remover = RecordingRemover::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            true,
            TargetOs::Darwin,
            choose_all,
            &remover,
        )
        .unwrap();
        assert!(!remover.was_called());
    }

    #[test]
    fn passes_selected_subset_to_remover() {
        let remover = RecordingRemover::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            false,
            TargetOs::Darwin,
            choose_first,
            &remover,
        )
        .unwrap();
        let call = remover.last_call().unwrap();
        assert_eq!(call.len(), 1);
    }

    #[test]
    fn all_selected_calls_remover_with_all_programs() {
        let remover = RecordingRemover::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            false,
            TargetOs::Darwin,
            choose_all,
            &remover,
        )
        .unwrap();
        assert!(remover.was_called());
        let programs = remover.last_call().unwrap();
        assert!(programs.contains(&"git".to_owned()));
    }
}
