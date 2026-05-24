use std::path::Path;

use anyhow::{Context, Result};
use kaizen_core::{
    HookRunner, KaizenEngine, OnFailure, ProcessCommand, ProcessExecutor, TargetOs, UpdateBackend,
    UpdateOpts, UserConfig,
};
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
        &crate::executor::StdProcessExecutor,
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
    executor: &dyn ProcessExecutor,
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
    let update_hooks = engine
        .update_hooks_for_enabled_features(&filtered)
        .context("failed to read feature registry")?;

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
        if !update_hooks.is_empty() {
            println!();
            println!("  feature hooks (dry-run):");
            for hook in &update_hooks {
                println!("  {}  {}", "→".dimmed(), hook.run.join(" ").dimmed());
            }
        }
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

    let update_hooks = update_hooks;
    for hook in update_hooks {
        let label = hook.run.join(" ");
        output::header(&label);
        let Some((bin, args)) = hook.run.split_first() else {
            continue;
        };
        let result = executor.execute(ProcessCommand::run(bin, args.iter().map(String::as_str)));
        match (result, &hook.on_failure) {
            (Ok(_), _) => output::item_ok(&label),
            (Err(e), OnFailure::Warn) => output::item_warn(&format!("{label}: {e}")),
            (Err(e), OnFailure::Fail) => return Err(anyhow::anyhow!("{label}: {e}")),
        }
    }

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
    use std::sync::{Arc, Mutex};

    use kaizen_core::{
        HookRunner, KaizenEngine, KaizenError, ProcessCommand, ProcessExecutor, ProcessOutput,
        ProgressReporter, UpdateBackend, UpdateOpts, UpdateReport, WorkflowPlan,
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
        calls: Mutex<Vec<Vec<String>>>,
    }

    impl RecordingHookRunner {
        fn new() -> Self {
            Self {
                calls: Mutex::new(vec![]),
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

    struct RecordingExecutor(Mutex<Vec<String>>);

    impl RecordingExecutor {
        fn new() -> Self {
            Self(Mutex::new(vec![]))
        }
        fn cmds(&self) -> Vec<String> {
            self.0.lock().unwrap().clone()
        }
    }

    impl ProcessExecutor for RecordingExecutor {
        fn execute(&self, cmd: ProcessCommand) -> Result<ProcessOutput, KaizenError> {
            self.0.lock().unwrap().push(
                format!("{} {}", cmd.bin, cmd.args.join(" "))
                    .trim()
                    .to_owned(),
            );
            Ok(ProcessOutput::default())
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
            Arc::new(crate::filesystem::StdFileSystem),
        )
    }

    fn engine_with_cache(cache_json: &str) -> (KaizenEngine, tempfile::TempDir) {
        let tmp = tempfile::tempdir().unwrap();
        let cache_path = tmp.path().join("feature-meta.json");
        std::fs::write(&cache_path, cache_json).unwrap();
        let engine = KaizenEngine::cache_only(Arc::new(crate::filesystem::StdFileSystem))
            .with_nix_cache(cache_path);
        (engine, tmp)
    }

    fn config_with_feature(dir: &std::path::Path, feature: &str) -> PathBuf {
        let path = dir.join("config.toml");
        std::fs::write(
            &path,
            format!(
                "schema_version=1\n[dotfiles]\nbackend=\"chezmoi\"\n[features.{feature}]\nenabled=true\n"
            ),
        )
        .unwrap();
        path
    }

    fn run(
        engine: &KaizenEngine,
        config_path: &std::path::Path,
        dry_run: bool,
        backend: &dyn UpdateBackend,
        hooks: &dyn HookRunner,
        executor: &dyn ProcessExecutor,
    ) -> anyhow::Result<()> {
        run_with(
            engine,
            config_path,
            dry_run,
            false,
            vec![],
            false,
            "mock",
            backend,
            hooks,
            executor,
        )
    }

    #[test]
    fn dry_run_does_not_call_backend_update() {
        let backend = RecordingBackend::new();
        let hooks = RecordingHookRunner::new();
        let ex = RecordingExecutor::new();
        run(
            &fixture_engine(),
            &fixture_path("config-hooks.toml"),
            true,
            &backend,
            &hooks,
            &ex,
        )
        .unwrap();
        assert!(!backend.update_called.load(Ordering::Relaxed));
    }

    #[test]
    fn normal_run_calls_backend_update() {
        let backend = RecordingBackend::new();
        let hooks = RecordingHookRunner::new();
        let ex = RecordingExecutor::new();
        run(
            &fixture_engine(),
            &fixture_path("config-hooks.toml"),
            false,
            &backend,
            &hooks,
            &ex,
        )
        .unwrap();
        assert!(backend.update_called.load(Ordering::Relaxed));
    }

    #[test]
    fn post_update_hooks_called_after_update() {
        let backend = RecordingBackend::new();
        let hooks = RecordingHookRunner::new();
        let ex = RecordingExecutor::new();
        run(
            &fixture_engine(),
            &fixture_path("config-hooks.toml"),
            false,
            &backend,
            &hooks,
            &ex,
        )
        .unwrap();
        assert!(
            hooks.was_called(),
            "post_update hooks must run after update"
        );
    }

    #[test]
    fn dry_run_skips_post_update_hooks() {
        let backend = RecordingBackend::new();
        let hooks = RecordingHookRunner::new();
        let ex = RecordingExecutor::new();
        run(
            &fixture_engine(),
            &fixture_path("config-hooks.toml"),
            true,
            &backend,
            &hooks,
            &ex,
        )
        .unwrap();
        assert!(!hooks.was_called(), "dry-run must not call hooks");
    }

    #[test]
    fn update_runs_feature_update_hooks_not_bump_before() {
        let cache_json = r#"{
            "ai": {
                "update":  [{"run": ["pi", "update", "--extensions"], "onFailure": "warn"}],
                "bump": {
                    "before": [{"run": ["pi", "sync", "--all"], "onFailure": "warn"}],
                    "run": [],
                    "capture": []
                }
            }
        }"#;
        let (engine, tmp) = engine_with_cache(cache_json);
        let cfg_path = config_with_feature(tmp.path(), "ai");
        let backend = RecordingBackend::new();
        let hooks = RecordingHookRunner::new();
        let ex = RecordingExecutor::new();
        run(&engine, &cfg_path, false, &backend, &hooks, &ex).unwrap();
        let cmds = ex.cmds();
        assert!(
            cmds.contains(&"pi update --extensions".to_owned()),
            "update field must be executed: {cmds:?}"
        );
        assert!(
            !cmds.iter().any(|c| c.contains("pi sync")),
            "bump.before must not run during update: {cmds:?}"
        );
    }

    #[test]
    fn dry_run_skips_feature_update_hooks() {
        let cache_json = r#"{
            "ai": {
                "update": [{"run": ["pi", "update", "--extensions"], "onFailure": "warn"}]
            }
        }"#;
        let (engine, tmp) = engine_with_cache(cache_json);
        let cfg_path = config_with_feature(tmp.path(), "ai");
        let backend = RecordingBackend::new();
        let hooks = RecordingHookRunner::new();
        let ex = RecordingExecutor::new();
        run(&engine, &cfg_path, true, &backend, &hooks, &ex).unwrap();
        assert!(
            ex.cmds().is_empty(),
            "dry-run must not execute feature update hooks: {:?}",
            ex.cmds()
        );
    }

    #[test]
    fn dry_run_shows_feature_update_hooks() {
        let cache_json = r#"{
            "ai": {
                "update": [{"run": ["pi", "update", "--extensions"], "onFailure": "warn"}]
            }
        }"#;
        let (engine, tmp) = engine_with_cache(cache_json);
        let cfg_path = config_with_feature(tmp.path(), "ai");
        let backend = RecordingBackend::new();
        let hooks = RecordingHookRunner::new();
        let ex = RecordingExecutor::new();
        // Must succeed without error in dry-run mode even with feature hooks present.
        run(&engine, &cfg_path, true, &backend, &hooks, &ex).unwrap();
        // Executor must not be called — hooks are shown, not executed.
        assert!(
            ex.cmds().is_empty(),
            "dry-run must not execute hooks: {:?}",
            ex.cmds()
        );
        // Backend must not be called either.
        assert!(!backend.update_called.load(Ordering::Relaxed));
    }
}
