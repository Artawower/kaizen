use std::path::Path;

use anyhow::{Context, Result};
use kaizen_core::{
    nix_feature_cache, KaizenEngine, KaizenError, OnFailure, ProcessCommand, ProcessExecutor,
    ProgressReporter, UserConfig,
};
use owo_colors::OwoColorize;

use crate::output;

pub fn run(
    only: &[String],
    dry_run: bool,
    executor: &dyn ProcessExecutor,
    engine: &KaizenEngine,
    config_path: &Path,
    reporter: &dyn ProgressReporter,
) -> Result<()> {
    output::page_header(if dry_run { "bump  (dry-run)" } else { "bump" });

    let config = kaizen_core::config::load_with(config_path, &crate::filesystem::StdFileSystem)
        .or_else(|e| match e {
            KaizenError::ConfigNotFound { .. } => Ok(UserConfig::default()),
            e => Err(e),
        })
        .with_context(|| format!("failed to load config from {}", config_path.display()))?;

    let mut bumps = engine
        .bump_for_enabled_features(&config)
        .context("failed to read feature registry")?;

    if !only.is_empty() {
        bumps.retain(|(name, _)| only.contains(name));
        if bumps.is_empty() {
            anyhow::bail!("no features matched {:?}", only);
        }
    }

    if bumps.is_empty() {
        output::item_warn("no enabled features with bump workflows defined");
        return Ok(());
    }

    let home = dirs::home_dir();

    for (name, bump) in &bumps {
        output::header(name);

        for hook in &bump.before {
            run_hook(
                hook,
                home.as_deref(),
                dry_run,
                "[before]",
                executor,
                reporter,
            )?;
        }

        for hook in &bump.run {
            run_hook(hook, home.as_deref(), dry_run, "", executor, reporter)?;
        }

        for raw_path in &bump.capture {
            let expanded = expand_home(raw_path, home.as_deref());
            if dry_run {
                println!("  {}  chezmoi re-add {}", "→".dimmed(), raw_path.dimmed());
                continue;
            }
            reporter.step(&format!("→ chezmoi re-add {expanded}"));
            executor
                .execute(ProcessCommand::run("chezmoi", ["re-add", &expanded]))
                .map_err(|e| anyhow::anyhow!("chezmoi re-add {expanded} failed: {e}"))?;
        }

        if !dry_run {
            output::item_ok(&format!("{name} done"));
        }
    }

    if !dry_run {
        println!();
        output::item_ok("bump complete — commit the updated lock files");
    }
    Ok(())
}

fn run_hook(
    hook: &nix_feature_cache::UpdateHook,
    home: Option<&Path>,
    dry_run: bool,
    tag: &str,
    executor: &dyn ProcessExecutor,
    reporter: &dyn ProgressReporter,
) -> Result<()> {
    let expanded: Vec<String> = hook.run.iter().map(|p| expand_home(p, home)).collect();
    let label = expanded.join(" ");
    if dry_run {
        if tag.is_empty() {
            println!("  {}  {}", "→".dimmed(), label.dimmed());
        } else {
            println!("  {}  {} {}", "→".dimmed(), label.dimmed(), tag.dimmed());
        }
        return Ok(());
    }
    reporter.step(&format!("→ {label}"));
    let Some((bin, args)) = expanded.split_first() else {
        return Ok(());
    };
    let result = executor.execute(ProcessCommand::run(bin, args.iter().map(String::as_str)));
    match (result, &hook.on_failure) {
        (Ok(_), _) => output::item_ok(&label),
        (Err(e), OnFailure::Warn) => output::item_warn(&format!("{label}: {e}")),
        (Err(e), OnFailure::Fail) => anyhow::bail!("{label}: {e}"),
    }
    Ok(())
}

pub(crate) fn expand_home(path: &str, home: Option<&Path>) -> String {
    match home {
        Some(h) if path.starts_with("~/") => format!("{}/{}", h.display(), &path[2..]),
        _ => path.to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::Arc;
    use std::sync::Mutex;

    use crate::filesystem::StdFileSystem;
    use kaizen_core::{KaizenError, ProcessCommand, ProcessExecutor, ProcessOutput};

    use super::*;
    use crate::reporter::StderrReporter;

    const FIXTURE_JSON: &str = r#"{
        "mise": {
            "description": "Mise toolchains",
            "category": "dev",
            "bump": {
                "before": [{"run": ["mise", "install"], "onFailure": "fail"}],
                "run": [{"run": ["mise-bump"], "onFailure": "fail"}],
                "capture": ["/tmp/mise.lock"]
            }
        },
        "nix": {
            "description": "Nix flake",
            "category": "system",
            "bump": {
                "run": [{"run": ["nix", "flake", "update"], "onFailure": "fail"}],
                "capture": ["/tmp/flake.lock"]
            }
        }
    }"#;

    struct Recording(Mutex<Vec<String>>);

    impl Recording {
        fn new() -> Self {
            Self(Mutex::new(vec![]))
        }
        fn cmds(&self) -> Vec<String> {
            self.0.lock().unwrap().clone()
        }
    }

    impl ProcessExecutor for Recording {
        fn execute(&self, cmd: ProcessCommand) -> Result<ProcessOutput, KaizenError> {
            self.0.lock().unwrap().push(
                format!("{} {}", cmd.bin, cmd.args.join(" "))
                    .trim()
                    .to_owned(),
            );
            Ok(ProcessOutput {
                stdout: String::new(),
                stderr: String::new(),
            })
        }
    }

    /// Executor that records all commands and fails when the command contains `fail_on`.
    struct FailOn {
        fail_on: String,
        log: Mutex<Vec<String>>,
    }

    impl FailOn {
        fn new(fail_on: &str) -> Self {
            Self {
                fail_on: fail_on.to_owned(),
                log: Mutex::new(vec![]),
            }
        }
        fn cmds(&self) -> Vec<String> {
            self.log.lock().unwrap().clone()
        }
    }

    impl ProcessExecutor for FailOn {
        fn execute(&self, cmd: ProcessCommand) -> Result<ProcessOutput, KaizenError> {
            let full = format!("{} {}", cmd.bin, cmd.args.join(" "))
                .trim()
                .to_owned();
            self.log.lock().unwrap().push(full.clone());
            if full.contains(&self.fail_on) {
                Err(KaizenError::CommandFailed {
                    cmd: full,
                    code: Some(1),
                })
            } else {
                Ok(ProcessOutput {
                    stdout: String::new(),
                    stderr: String::new(),
                })
            }
        }
    }

    fn engine_with_cache(cache_content: &str) -> (KaizenEngine, tempfile::TempDir) {
        let tmp = tempfile::tempdir().unwrap();
        let cache_path = tmp.path().join("feature-meta.json");
        std::fs::write(&cache_path, cache_content).unwrap();
        let engine = KaizenEngine::cache_only(Arc::new(StdFileSystem)).with_nix_cache(cache_path);
        (engine, tmp)
    }

    fn config_with_features(dir: &std::path::Path, features: &[&str]) -> PathBuf {
        let cfg_path = dir.join("config.toml");
        let mut content = "schema_version=1\n[dotfiles]\nbackend=\"chezmoi\"\n".to_string();
        for f in features {
            content.push_str(&format!("[features.{}]\nenabled=true\n", f));
        }
        std::fs::write(&cfg_path, content).unwrap();
        cfg_path
    }

    #[test]
    fn dry_run_shows_per_feature_before_run_capture() {
        let (engine, tmp) = engine_with_cache(FIXTURE_JSON);
        let cfg_path = config_with_features(tmp.path(), &["mise"]);
        let ex = Recording::new();
        run(&[], true, &ex, &engine, &cfg_path, &StderrReporter).unwrap();
        assert!(
            ex.cmds().is_empty(),
            "dry-run executes nothing: {:?}",
            ex.cmds()
        );
    }

    #[test]
    fn only_filter_runs_single_feature() {
        let (engine, tmp) = engine_with_cache(FIXTURE_JSON);
        let cfg_path = config_with_features(tmp.path(), &["mise", "nix"]);
        let ex = Recording::new();
        run(
            &["mise".to_string()],
            false,
            &ex,
            &engine,
            &cfg_path,
            &StderrReporter,
        )
        .unwrap();
        let cmds = ex.cmds();
        assert!(cmds.contains(&"mise install".to_owned()), "{cmds:?}");
        assert!(cmds.contains(&"mise-bump".to_owned()), "{cmds:?}");
        assert!(!cmds.iter().any(|c| c.contains("nix")), "{cmds:?}");
    }

    #[test]
    fn capture_calls_chezmoi_re_add() {
        let (engine, tmp) = engine_with_cache(FIXTURE_JSON);
        let cfg_path = config_with_features(tmp.path(), &["nix"]);
        let ex = Recording::new();
        run(&[], false, &ex, &engine, &cfg_path, &StderrReporter).unwrap();
        let cmds = ex.cmds();
        assert!(
            cmds.iter()
                .any(|c| c.contains("re-add") && c.contains("flake.lock")),
            "{cmds:?}"
        );
    }

    #[test]
    fn before_run_capture_execute_in_order() {
        let (engine, tmp) = engine_with_cache(FIXTURE_JSON);
        let cfg_path = config_with_features(tmp.path(), &["mise"]);
        let ex = Recording::new();
        run(&[], false, &ex, &engine, &cfg_path, &StderrReporter).unwrap();
        let cmds = ex.cmds();
        let before_idx = cmds
            .iter()
            .position(|c| c == "mise install")
            .expect("mise install not found");
        let run_idx = cmds
            .iter()
            .position(|c| c == "mise-bump")
            .expect("mise-bump not found");
        let capture_idx = cmds
            .iter()
            .position(|c| c.contains("re-add") && c.contains("mise.lock"))
            .expect("chezmoi re-add not found");
        assert!(before_idx < run_idx, "before must precede run: {cmds:?}");
        assert!(run_idx < capture_idx, "run must precede capture: {cmds:?}");
    }

    #[test]
    fn on_failure_fail_returns_err_and_skips_capture() {
        let cache = r#"{
            "mise": {
                "bump": {
                    "run": [{"run": ["mise-bump"], "onFailure": "fail"}],
                    "capture": ["/tmp/mise.lock"]
                }
            }
        }"#;
        let (engine, tmp) = engine_with_cache(cache);
        let cfg_path = config_with_features(tmp.path(), &["mise"]);
        let ex = FailOn::new("mise-bump");
        let result = run(&[], false, &ex, &engine, &cfg_path, &StderrReporter);
        assert!(result.is_err(), "onFailure=fail must propagate error");
        let cmds = ex.cmds();
        assert!(
            !cmds.iter().any(|c| c.contains("re-add")),
            "capture must not run after fail: {cmds:?}"
        );
    }

    #[test]
    fn on_failure_warn_continues_and_runs_capture() {
        let cache = r#"{
            "mise": {
                "bump": {
                    "run": [{"run": ["mise-bump"], "onFailure": "warn"}],
                    "capture": ["/tmp/mise.lock"]
                }
            }
        }"#;
        let (engine, tmp) = engine_with_cache(cache);
        let cfg_path = config_with_features(tmp.path(), &["mise"]);
        let ex = FailOn::new("mise-bump");
        let result = run(&[], false, &ex, &engine, &cfg_path, &StderrReporter);
        assert!(
            result.is_ok(),
            "onFailure=warn must not propagate error: {result:?}"
        );
        let cmds = ex.cmds();
        assert!(
            cmds.iter()
                .any(|c| c.contains("re-add") && c.contains("mise.lock")),
            "capture must still run after warn: {cmds:?}"
        );
    }

    #[test]
    fn kaizen_update_uses_update_not_bump() {
        // update and bump.before intentionally use DIFFERENT commands so the test
        // fails if the implementation reads the wrong field.
        let cache_json = r#"{
            "ai": {
                "update": [{"run": ["pi", "update", "--extensions"], "onFailure": "warn"}],
                "bump": {
                    "before": [{"run": ["pi", "sync", "--all"], "onFailure": "warn"}],
                    "run": [],
                    "capture": ["~/.pi/agent/settings.json"]
                }
            }
        }"#;
        let (engine, tmp) = engine_with_cache(cache_json);
        let cfg_path = config_with_features(tmp.path(), &["ai"]);
        let config = kaizen_core::config::load_with(&cfg_path, &StdFileSystem).unwrap();

        let update_hooks = engine.update_hooks_for_enabled_features(&config).unwrap();
        let bump_workflows = engine.bump_for_enabled_features(&config).unwrap();

        assert!(!update_hooks.is_empty(), "update hooks must be present");
        assert!(!bump_workflows.is_empty(), "bump workflow must be present");

        let update_cmds: Vec<_> = update_hooks.iter().map(|h| h.run.join(" ")).collect();
        let bump_before_cmds: Vec<_> = bump_workflows
            .iter()
            .flat_map(|(_, b)| b.before.iter().map(|h| h.run.join(" ")))
            .collect();

        // update reads the `update` field → "pi update --extensions"
        assert_eq!(
            update_cmds,
            vec!["pi update --extensions"],
            "update must read from `update` field: {update_cmds:?}"
        );
        // bump reads the `bump.before` field → "pi sync --all"
        assert_eq!(
            bump_before_cmds,
            vec!["pi sync --all"],
            "bump.before must read from `bump.before` field: {bump_before_cmds:?}"
        );
        // The two must differ — if they were equal the test would be worthless
        assert_ne!(
            update_cmds, bump_before_cmds,
            "update and bump.before must use different commands"
        );
    }

    #[test]
    fn only_filter_unknown_feature_returns_error() {
        let (engine, tmp) = engine_with_cache(FIXTURE_JSON);
        let cfg_path = config_with_features(tmp.path(), &["mise"]);
        let ex = Recording::new();
        let result = run(
            &["unknown".to_string()],
            false,
            &ex,
            &engine,
            &cfg_path,
            &StderrReporter,
        );
        assert!(result.is_err(), "expected error for unknown feature");
        assert!(ex.cmds().is_empty());
    }

    #[test]
    fn no_cache_returns_empty_without_error() {
        let engine = KaizenEngine::cache_only(Arc::new(StdFileSystem));
        let tmp = tempfile::tempdir().unwrap();
        let cfg_path = config_with_features(tmp.path(), &["mise"]);
        let ex = Recording::new();
        run(&[], false, &ex, &engine, &cfg_path, &StderrReporter).unwrap();
        assert!(ex.cmds().is_empty());
    }

    #[test]
    fn invalid_config_returns_error() {
        let (engine, tmp) = engine_with_cache(FIXTURE_JSON);
        let cfg_path = tmp.path().join("config.toml");
        std::fs::write(&cfg_path, "not [ valid toml =").unwrap();
        let ex = Recording::new();
        let result = run(&[], false, &ex, &engine, &cfg_path, &StderrReporter);
        assert!(result.is_err(), "broken config must return error");
    }

    #[test]
    fn missing_config_treated_as_no_features() {
        let (engine, tmp) = engine_with_cache(FIXTURE_JSON);
        let cfg_path = tmp.path().join("nonexistent.toml");
        let ex = Recording::new();
        run(&[], false, &ex, &engine, &cfg_path, &StderrReporter).unwrap();
        assert!(ex.cmds().is_empty(), "no config = no enabled features");
    }

    #[test]
    fn expand_home_replaces_tilde() {
        let home = std::path::Path::new("/home/user");
        assert_eq!(
            expand_home("~/.config/mise.lock", Some(home)),
            "/home/user/.config/mise.lock"
        );
    }

    #[test]
    fn expand_home_leaves_absolute_paths() {
        assert_eq!(expand_home("/etc/foo", None), "/etc/foo");
    }
}
