use std::path::Path;

use anyhow::{Context, Result};
use kaizen_core::{
    KaizenEngine, KaizenError, ProcessCommand, ProcessExecutor, ProgressReporter, UserConfig,
};
use owo_colors::OwoColorize;

use crate::{commands::bump::expand_home, output};

pub fn run(
    only: &[String],
    dry_run: bool,
    executor: &dyn ProcessExecutor,
    engine: &KaizenEngine,
    config_path: &Path,
    reporter: &dyn ProgressReporter,
) -> Result<()> {
    output::page_header(if dry_run {
        "re-add  (dry-run)"
    } else {
        "re-add"
    });

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
        output::item_warn("no enabled features with capture paths defined");
        return Ok(());
    }

    let home = dirs::home_dir();

    for (name, bump) in &bumps {
        if bump.capture.is_empty() {
            continue;
        }
        output::header(name);

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
        output::item_ok("re-add complete");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::{Arc, Mutex};

    use crate::filesystem::StdFileSystem;
    use kaizen_core::{KaizenEngine, KaizenError, ProcessCommand, ProcessExecutor, ProcessOutput};

    use super::*;
    use crate::reporter::StderrReporter;

    const FIXTURE_JSON: &str = r#"{
        "mise": {
            "bump": {
                "before": [{"run": ["mise", "install"], "onFailure": "fail"}],
                "run": [{"run": ["mise-bump"], "onFailure": "fail"}],
                "capture": ["/tmp/mise.lock"]
            }
        },
        "nix-system": {
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
            Ok(ProcessOutput::default())
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
    fn dry_run_shows_paths_without_executing() {
        let (engine, tmp) = engine_with_cache(FIXTURE_JSON);
        let cfg_path = config_with_features(tmp.path(), &["mise"]);
        let ex = Recording::new();
        run(&[], true, &ex, &engine, &cfg_path, &StderrReporter).unwrap();
        assert!(
            ex.cmds().is_empty(),
            "dry-run must not execute: {:?}",
            ex.cmds()
        );
    }

    #[test]
    fn only_filter_restricts_to_named_feature() {
        let (engine, tmp) = engine_with_cache(FIXTURE_JSON);
        let cfg_path = config_with_features(tmp.path(), &["mise", "nix-system"]);
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
        assert!(
            cmds.iter()
                .any(|c| c.contains("re-add") && c.contains("mise.lock")),
            "mise.lock must be re-added: {cmds:?}"
        );
        assert!(
            !cmds.iter().any(|c| c.contains("flake.lock")),
            "flake.lock must not be re-added when filtered: {cmds:?}"
        );
    }

    #[test]
    fn capture_calls_chezmoi_re_add_without_running_bump_commands() {
        let (engine, tmp) = engine_with_cache(FIXTURE_JSON);
        let cfg_path = config_with_features(tmp.path(), &["mise"]);
        let ex = Recording::new();
        run(&[], false, &ex, &engine, &cfg_path, &StderrReporter).unwrap();
        let cmds = ex.cmds();
        assert!(
            cmds.iter()
                .any(|c| c.contains("re-add") && c.contains("mise.lock")),
            "re-add must be called: {cmds:?}"
        );
        assert!(
            !cmds.iter().any(|c| c == "mise install" || c == "mise-bump"),
            "bump commands must not run in re-add: {cmds:?}"
        );
    }

    #[test]
    fn only_filter_unknown_returns_error() {
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
        assert!(result.is_err(), "unknown feature must return error");
    }
}
