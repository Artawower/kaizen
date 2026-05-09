use std::path::Path;

use anyhow::Result;
use kaizen_core::{HookRunner, KaizenEngine, TargetOs, UpdateBackend, UpdateOpts, UserConfig};
use owo_colors::OwoColorize;

use crate::{
    backend::detect_backend, hooks, hooks::ShellHookRunner, output, reporter::StderrReporter,
    selector,
};

pub fn run(
    engine: &KaizenEngine,
    config_path: &Path,
    dry_run: bool,
    update_flake: bool,
    features: Vec<String>,
    interactive: bool,
) -> Result<()> {
    let os = TargetOs::detect();
    let backend = detect_backend(os);
    run_with(
        engine,
        config_path,
        dry_run,
        update_flake,
        features,
        interactive,
        backend.id(),
        backend.as_ref(),
        &ShellHookRunner,
    )
}

#[allow(clippy::too_many_arguments)]
fn run_with(
    engine: &KaizenEngine,
    config_path: &Path,
    dry_run: bool,
    update_flake: bool,
    features: Vec<String>,
    interactive: bool,
    backend_id: &str,
    backend: &dyn UpdateBackend,
    hook_runner: &dyn HookRunner,
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

    let mut filtered = config.clone();
    for (name, sel) in filtered.features.iter_mut() {
        if !selected.contains(name) {
            sel.enabled = false;
        }
    }

    let os = TargetOs::detect();
    let plan = engine.build_workflow_plan(&filtered, os)?;

    output::kv("backend", backend_id);
    if update_flake {
        output::kv("flake update", "yes");
    }
    println!();

    if dry_run {
        println!(
            "  {}  would run update for {} feature(s)",
            "→".dimmed(),
            selected.len()
        );
        println!();
        println!("  Run without --dry-run to apply.");
        return Ok(());
    }

    let report = backend.update(
        &plan,
        &UpdateOpts {
            dry_run,
            update_flake,
        },
        &StderrReporter,
    )?;

    for w in &report.warnings {
        output::item_warn(w);
    }

    hooks::run(&plan.hook_plan.post_update, dry_run, hook_runner)?;

    println!();
    output::item_ok(&format!("updated {} feature(s)", selected.len()));
    Ok(())
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
        return selector::multi_select("Select features to update", items);
    }
    if !features.is_empty() {
        return Ok(Some(features));
    }
    Ok(Some(
        config
            .features
            .iter()
            .filter(|(_, s)| s.enabled)
            .map(|(k, _)| k.clone())
            .collect(),
    ))
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicBool, Ordering};

    use kaizen_core::{
        HookRunner, KaizenEngine, KaizenError, ProgressReporter, UpdateBackend, UpdateOpts,
        UpdateReport, WorkflowPlan,
    };

    use super::run_with;

    struct RecordingBackend {
        update_called: AtomicBool,
    }

    impl RecordingBackend {
        fn new() -> Self {
            Self {
                update_called: AtomicBool::new(false),
            }
        }
    }

    impl UpdateBackend for RecordingBackend {
        fn update(
            &self,
            _: &WorkflowPlan,
            _: &UpdateOpts,
            _: &dyn ProgressReporter,
        ) -> Result<UpdateReport, KaizenError> {
            self.update_called.store(true, Ordering::Relaxed);
            Ok(UpdateReport::default())
        }
    }

    struct RecordingHookRunner {
        calls: std::sync::Mutex<Vec<Vec<String>>>,
    }

    impl RecordingHookRunner {
        fn new() -> Self {
            Self {
                calls: std::sync::Mutex::new(vec![]),
            }
        }
        fn was_called(&self) -> bool {
            !self.calls.lock().unwrap().is_empty()
        }
    }

    impl HookRunner for RecordingHookRunner {
        fn run(&self, cmds: &[String]) -> Result<(), KaizenError> {
            self.calls.lock().unwrap().push(cmds.to_vec());
            Ok(())
        }
    }

    fn fixture_path(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name)
    }

    fn fixture_engine() -> KaizenEngine {
        KaizenEngine::new(
            fixture_path("features"),
            std::sync::Arc::new(crate::filesystem::StdFileSystem),
        )
    }

    fn run(
        engine: &KaizenEngine,
        dry_run: bool,
        backend: &dyn UpdateBackend,
        hooks: &dyn HookRunner,
    ) -> anyhow::Result<()> {
        run_with(
            engine,
            &fixture_path("config-hooks.toml"),
            dry_run,
            false,
            vec![],
            false,
            "mock",
            backend,
            hooks,
        )
    }

    #[test]
    fn dry_run_does_not_call_backend_update() {
        let backend = RecordingBackend::new();
        let hooks = RecordingHookRunner::new();
        run(&fixture_engine(), true, &backend, &hooks).unwrap();
        assert!(!backend.update_called.load(Ordering::Relaxed));
    }

    #[test]
    fn normal_run_calls_backend_update() {
        let backend = RecordingBackend::new();
        let hooks = RecordingHookRunner::new();
        run(&fixture_engine(), false, &backend, &hooks).unwrap();
        assert!(backend.update_called.load(Ordering::Relaxed));
    }

    #[test]
    fn post_update_hooks_called_after_update() {
        let backend = RecordingBackend::new();
        let hooks = RecordingHookRunner::new();
        run(&fixture_engine(), false, &backend, &hooks).unwrap();
        assert!(
            hooks.was_called(),
            "post_update hooks must run after update"
        );
    }

    #[test]
    fn dry_run_skips_post_update_hooks() {
        let backend = RecordingBackend::new();
        let hooks = RecordingHookRunner::new();
        run(&fixture_engine(), true, &backend, &hooks).unwrap();
        assert!(!hooks.was_called(), "dry-run must not call hooks");
    }
}
