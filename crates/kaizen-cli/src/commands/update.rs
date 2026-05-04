use std::path::Path;

use anyhow::Result;
use kaizen_core::{
    HookRunner, KaizenEngine, ShellHookRunner, TargetOs, Updater, UptInstaller, UserConfig,
};
use owo_colors::OwoColorize;

use crate::{ensure, hooks, output, selector};

pub fn run(
    engine: &KaizenEngine,
    config_path: &Path,
    dry_run: bool,
    features: Vec<String>,
    interactive: bool,
) -> Result<()> {
    output::page_header(if dry_run {
        "update  (dry-run)"
    } else {
        "update"
    });

    let config = engine.load_config(config_path)?;
    output::warn_if_schema_outdated(&config);

    let selected = resolve_features(&config, features, interactive)?;
    let Some(selected) = selected else {
        return Ok(());
    };

    if selected.is_empty() {
        output::item_warn("no enabled features — nothing to update");
        return Ok(());
    }

    run_with(
        engine,
        &config,
        dry_run,
        TargetOs::detect(),
        selected,
        &UptInstaller,
        &ShellHookRunner,
    )
}

fn resolve_features(
    config: &UserConfig,
    features: Vec<String>,
    interactive: bool,
) -> Result<Option<Vec<String>>> {
    if interactive {
        let items: Vec<selector::Item> = config
            .features
            .iter()
            .filter(|(_, s)| s.enabled)
            .map(|(name, _)| selector::Item {
                name: name.clone(),
                desc: None,
                selected: true,
            })
            .collect();
        selector::multi_select("Select features to update", items)
    } else if !features.is_empty() {
        Ok(Some(features))
    } else {
        Ok(Some(
            config
                .features
                .iter()
                .filter(|(_, s)| s.enabled)
                .map(|(k, _)| k.clone())
                .collect(),
        ))
    }
}

fn run_with(
    engine: &KaizenEngine,
    config: &UserConfig,
    dry_run: bool,
    target_os: TargetOs,
    selected_features: Vec<String>,
    updater: &dyn Updater,
    hook_runner: &dyn HookRunner,
) -> Result<()> {
    let mut filtered = config.clone();
    for (name, selection) in filtered.features.iter_mut() {
        if !selected_features.contains(name) {
            selection.enabled = false;
        }
    }

    let plan = engine.build_workflow_plan(&filtered, target_os)?;

    let all_upgraded = if !plan.install_plan.programs.is_empty() {
        if !dry_run {
            ensure::require(&[&ensure::UPT])?;
        }
        execute_upgrade(&plan.install_plan.programs, dry_run, updater)?
    } else {
        true
    };

    if !plan.install_plan.mise_tools.is_empty() {
        if !dry_run {
            ensure::require(&[&ensure::MISE])?;
        }
        let tool_names: Vec<String> = plan.install_plan.mise_tools.keys().cloned().collect();
        execute_mise_upgrade(&tool_names, dry_run)?
    }

    if all_upgraded {
        hooks::run(&plan.hook_plan.post_update, dry_run, hook_runner)?;
    } else {
        output::item_warn("skipping post_update hooks — some packages failed to upgrade");
    }

    if !dry_run {
        println!();
        output::item_ok(&format!("updated {} feature(s)", selected_features.len()));
    }

    Ok(())
}

fn execute_upgrade(programs: &[String], dry_run: bool, updater: &dyn Updater) -> Result<bool> {
    let preview = updater.preview_upgrade(programs);
    output::header(&format!("Upgrade packages ({})", programs.len()));
    for chunk in programs.chunks(4) {
        let row: Vec<String> = chunk.iter().map(|p| format!("{p:<20}")).collect();
        println!("  {}", row.join(""));
    }
    println!();

    if dry_run {
        println!("  {}  {}", "→".dimmed(), preview.dimmed());
        println!();
        return Ok(true);
    }

    println!("  {}  {}", "→".bold(), preview);
    println!();
    match updater.upgrade(programs) {
        Ok(()) => {
            output::item_ok(&format!("{} package(s) upgraded", programs.len()));
            Ok(true)
        }
        Err(kaizen_core::KaizenError::InstallerPartialFailure { failed, .. }) => {
            let ok = programs.len() - failed.len();
            if ok > 0 {
                output::item_ok(&format!("{ok} package(s) upgraded"));
            }
            for pkg in &failed {
                output::item_warn(&format!("{pkg}: failed to upgrade"));
            }
            Ok(false)
        }
        Err(e) => Err(e.into()),
    }
}

fn execute_mise_upgrade(tools: &[String], dry_run: bool) -> Result<()> {
    output::header(&format!("Upgrade mise tools ({})", tools.len()));
    for name in tools {
        println!("  {}", name);
    }
    println!();

    if dry_run {
        println!(
            "  {}  mise upgrade {}",
            "→".dimmed(),
            tools.join(" ").dimmed()
        );
        println!();
        return Ok(());
    }

    println!("  {}  mise upgrade {}", "→".bold(), tools.join(" "));
    println!();
    let status = std::process::Command::new("mise")
        .arg("upgrade")
        .args(tools)
        .status()?;
    if !status.success() {
        anyhow::bail!("mise upgrade failed");
    }
    output::item_ok("mise tools upgraded");
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::path::PathBuf;

    use kaizen_core::{HookRunner, KaizenError, Updater};

    use super::*;

    struct NoopUpdater;

    impl Updater for NoopUpdater {
        fn upgrade(&self, _programs: &[String]) -> Result<(), KaizenError> {
            Ok(())
        }

        fn preview_upgrade(&self, programs: &[String]) -> String {
            format!("mock upgrade {}", programs.join(" "))
        }
    }

    struct RecordingHookRunner {
        calls: RefCell<Vec<Vec<String>>>,
    }

    impl RecordingHookRunner {
        fn new() -> Self {
            Self {
                calls: RefCell::new(vec![]),
            }
        }

        fn was_called(&self) -> bool {
            !self.calls.borrow().is_empty()
        }
    }

    impl HookRunner for RecordingHookRunner {
        fn run(&self, commands: &[String]) -> Result<(), KaizenError> {
            self.calls.borrow_mut().push(commands.to_vec());
            Ok(())
        }
    }

    struct PartiallyFailingUpdater;

    impl Updater for PartiallyFailingUpdater {
        fn upgrade(&self, programs: &[String]) -> Result<(), KaizenError> {
            Err(KaizenError::InstallerPartialFailure {
                count: 1,
                failed: vec![programs.first().cloned().unwrap_or_default()],
            })
        }

        fn preview_upgrade(&self, programs: &[String]) -> String {
            format!("mock partial-fail upgrade {}", programs.join(" "))
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

    fn load_config(name: &str) -> UserConfig {
        kaizen_core::config::load(&fixture_path(name)).unwrap()
    }

    #[test]
    fn dry_run_does_not_call_hook_runner() {
        let hooks = RecordingHookRunner::new();
        let engine = fixture_engine();
        let config = load_config("config-hooks.toml");
        run_with(
            &engine,
            &config,
            true,
            TargetOs::Darwin,
            vec!["hooks-test".to_owned()],
            &NoopUpdater,
            &hooks,
        )
        .unwrap();
        assert!(!hooks.was_called());
    }

    #[test]
    fn hooks_called_after_successful_upgrade() {
        let hooks = RecordingHookRunner::new();
        let engine = fixture_engine();
        let config = load_config("config-hooks.toml");
        run_with(
            &engine,
            &config,
            false,
            TargetOs::Darwin,
            vec!["hooks-test".to_owned()],
            &NoopUpdater,
            &hooks,
        )
        .unwrap();
        assert!(hooks.was_called());
    }

    #[test]
    fn partial_upgrade_failure_skips_hooks() {
        let hooks = RecordingHookRunner::new();
        let engine = fixture_engine();
        let config = load_config("config-hooks.toml");
        run_with(
            &engine,
            &config,
            false,
            TargetOs::Darwin,
            vec!["hooks-test".to_owned()],
            &PartiallyFailingUpdater,
            &hooks,
        )
        .unwrap();
        assert!(!hooks.was_called());
    }

    #[test]
    fn selected_features_filter_plan() {
        let engine = fixture_engine();
        let config = load_config("config-minimal.toml");
        let hooks = RecordingHookRunner::new();
        run_with(
            &engine,
            &config,
            false,
            TargetOs::Darwin,
            vec!["core".to_owned()],
            &NoopUpdater,
            &hooks,
        )
        .unwrap();
    }

    #[test]
    fn resolve_features_returns_all_enabled_when_empty() {
        let config = load_config("config-minimal.toml");
        let result = resolve_features(&config, vec![], false).unwrap().unwrap();
        assert!(!result.is_empty());
        assert!(result.contains(&"core".to_owned()));
    }

    #[test]
    fn resolve_features_respects_named_list() {
        let config = load_config("config-minimal.toml");
        let result = resolve_features(&config, vec!["core".to_owned()], false)
            .unwrap()
            .unwrap();
        assert_eq!(result, vec!["core".to_owned()]);
    }
}
