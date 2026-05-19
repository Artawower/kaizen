use std::{collections::BTreeSet, path::Path};

use anyhow::{Context, Result};
use kaizen_core::{
    bump::{BumpManifest, BUMP_MANIFEST_FILE},
    manifest::KAIZEN_DIR,
    KaizenEngine, OnFailure, PathProvider, ProcessCommand, ProcessExecutor, ProgressReporter,
};
use owo_colors::OwoColorize;

use crate::output;

pub fn run(
    only: &[String],
    dry_run: bool,
    executor: &dyn ProcessExecutor,
    paths: &dyn PathProvider,
    source_path: Option<&Path>,
    engine: &KaizenEngine,
    config_path: &Path,
    reporter: &dyn ProgressReporter,
) -> Result<()> {
    output::page_header(if dry_run { "bump  (dry-run)" } else { "bump" });

    let manifest = load_manifest(paths, source_path)?;
    let steps = manifest.filter_steps(only);

    if steps.is_empty() {
        if only.is_empty() {
            output::item_warn("bump.toml has no steps defined");
            return Ok(());
        }
        let available = manifest
            .steps
            .iter()
            .map(|s| s.name.as_str())
            .collect::<Vec<_>>()
            .join(", ");
        anyhow::bail!("no steps matched {:?} — available: {}", only, available);
    }

    let home = dirs::home_dir();

    for step in &steps {
        output::header(&step.name);

        let expanded_run = step
            .run
            .iter()
            .map(|part| expand_home(part, home.as_deref()))
            .collect::<Vec<_>>();
        let (bin, args) = expanded_run
            .split_first()
            .with_context(|| format!("step '{}': run list is empty", step.name))?;

        if dry_run {
            println!("  {}  {}", "→".dimmed(), expanded_run.join(" ").dimmed());
            capture_step_outputs(
                std::iter::once(*step),
                home.as_deref(),
                true,
                executor,
                reporter,
            )?;
            continue;
        }

        reporter.step(&format!("→ {}", expanded_run.join(" ")));
        executor
            .execute(ProcessCommand::run(bin, args.iter().map(String::as_str)))
            .with_context(|| format!("step '{}': command failed", step.name))?;
        capture_step_outputs(
            std::iter::once(*step),
            home.as_deref(),
            false,
            executor,
            reporter,
        )?;

        output::item_ok(&format!("{} done", step.name));
    }

    let hooks_ran = run_feature_hooks(engine, config_path, only, dry_run, executor, reporter);
    if hooks_ran {
        capture_step_outputs(
            steps.iter().copied(),
            home.as_deref(),
            dry_run,
            executor,
            reporter,
        )?;
    }

    if !dry_run {
        println!();
        output::item_ok("bump complete — commit the updated lock files");
    }
    Ok(())
}

fn run_feature_hooks(
    engine: &KaizenEngine,
    config_path: &Path,
    only: &[String],
    dry_run: bool,
    executor: &dyn ProcessExecutor,
    reporter: &dyn ProgressReporter,
) -> bool {
    if !only.is_empty() {
        return false;
    }
    let config =
        match kaizen_core::config::load_with(config_path, &crate::filesystem::StdFileSystem) {
            Ok(c) => c,
            Err(_) => return false,
        };
    let hooks = match engine.update_hooks_for_enabled_features(&config) {
        Ok(h) => h,
        Err(_) => return false,
    };
    let mut ran = false;
    for hook in hooks {
        ran = true;
        let label = hook.run.join(" ");
        if dry_run {
            println!(
                "  {}  {} {}",
                "→".dimmed(),
                label.dimmed(),
                "[feature hook]".dimmed()
            );
            continue;
        }
        reporter.step(&format!("→ {label}"));
        let Some((bin, args)) = hook.run.split_first() else {
            continue;
        };
        let result = executor.execute(ProcessCommand::run(bin, args.iter().map(String::as_str)));
        match (result, &hook.on_failure) {
            (Ok(_), _) => output::item_ok(&label),
            (Err(e), OnFailure::Warn) => output::item_warn(&format!("{label}: {e}")),
            (Err(e), OnFailure::Fail) => {
                output::item_err(&format!("{label}: {e}"));
                return ran;
            }
        }
    }
    ran
}

fn capture_step_outputs<'a>(
    steps: impl IntoIterator<Item = &'a kaizen_core::bump::BumpStep>,
    home: Option<&Path>,
    dry_run: bool,
    executor: &dyn ProcessExecutor,
    reporter: &dyn ProgressReporter,
) -> Result<()> {
    for raw_path in steps
        .into_iter()
        .flat_map(|step| step.capture.iter())
        .collect::<BTreeSet<_>>()
    {
        let expanded = expand_home(raw_path, home);
        if dry_run {
            println!("  {}  chezmoi re-add {}", "→".dimmed(), raw_path.dimmed());
            continue;
        }
        reporter.step(&format!("→ chezmoi re-add {expanded}"));
        executor
            .execute(ProcessCommand::run("chezmoi", ["re-add", &expanded]))
            .with_context(|| format!("chezmoi re-add {expanded} failed"))?;
    }
    Ok(())
}

fn load_manifest(paths: &dyn PathProvider, source_path: Option<&Path>) -> Result<BumpManifest> {
    let source_manifest =
        source_path.map(|source| source.join(KAIZEN_DIR).join(BUMP_MANIFEST_FILE));
    let config_manifest = paths
        .config_dir()
        .map(|config_dir| config_dir.join("kaizen").join(BUMP_MANIFEST_FILE));

    for path in source_manifest.iter().chain(config_manifest.iter()) {
        if !path.exists() {
            continue;
        }
        let content = std::fs::read_to_string(path)
            .with_context(|| format!("failed to read {}", path.display()))?;
        return BumpManifest::from_toml(&content)
            .with_context(|| format!("failed to parse {}", path.display()));
    }

    Ok(BumpManifest::default())
}

fn expand_home(path: &str, home: Option<&std::path::Path>) -> String {
    match home {
        Some(h) if path.starts_with("~/") => {
            format!("{}/{}", h.display(), &path[2..])
        }
        _ => path.to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::Mutex;

    use crate::filesystem::StdFileSystem;
    use kaizen_core::{KaizenError, PathProvider, ProcessCommand, ProcessExecutor, ProcessOutput};
    use std::sync::Arc;

    fn empty_engine() -> KaizenEngine {
        KaizenEngine::cache_only(Arc::new(StdFileSystem))
    }
    fn no_config() -> &'static std::path::Path {
        std::path::Path::new("/nonexistent/config.toml")
    }

    use super::*;
    use crate::reporter::StderrReporter;

    const SAMPLE_MANIFEST: &str = r#"
[[steps]]
name    = "mise"
run     = ["mise", "upgrade", "--bump"]
capture = ["/tmp/mise.lock"]

[[steps]]
name    = "nix"
run     = ["nix", "flake", "update"]
capture = ["/tmp/flake.lock"]
"#;

    struct FixedPaths(Option<PathBuf>);
    impl PathProvider for FixedPaths {
        fn home_dir(&self) -> Option<PathBuf> {
            None
        }
        fn config_dir(&self) -> Option<PathBuf> {
            self.0.clone()
        }
        fn is_tool_available(&self, _: &str) -> bool {
            false
        }
    }

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

    fn write_manifest(dir: &std::path::Path) {
        write_manifest_content(dir, SAMPLE_MANIFEST);
    }

    fn write_manifest_content(dir: &std::path::Path, content: &str) {
        let kaizen_dir = dir.join("kaizen");
        std::fs::create_dir_all(&kaizen_dir).unwrap();
        std::fs::write(kaizen_dir.join(BUMP_MANIFEST_FILE), content).unwrap();
    }

    #[test]
    fn dry_run_no_config_dir_executes_nothing() {
        let ex = Recording::new();
        run(
            &[],
            true,
            &ex,
            &FixedPaths(None),
            None,
            &empty_engine(),
            no_config(),
            &StderrReporter,
        )
        .unwrap();
        assert!(ex.cmds().is_empty());
    }

    #[test]
    fn dry_run_with_manifest_executes_nothing() {
        let tmp = tempfile::tempdir().unwrap();
        write_manifest(tmp.path());
        let ex = Recording::new();
        run(
            &[],
            true,
            &ex,
            &FixedPaths(Some(tmp.path().to_owned())),
            None,
            &empty_engine(),
            no_config(),
            &StderrReporter,
        )
        .unwrap();
        assert!(ex.cmds().is_empty());
    }

    #[test]
    fn run_all_steps_executes_run_and_capture() {
        let tmp = tempfile::tempdir().unwrap();
        write_manifest(tmp.path());
        let ex = Recording::new();
        run(
            &[],
            false,
            &ex,
            &FixedPaths(Some(tmp.path().to_owned())),
            None,
            &empty_engine(),
            no_config(),
            &StderrReporter,
        )
        .unwrap();
        let cmds = ex.cmds();
        assert!(cmds.contains(&"mise upgrade --bump".to_owned()), "{cmds:?}");
        assert!(cmds.contains(&"nix flake update".to_owned()), "{cmds:?}");
        assert!(
            cmds.iter()
                .any(|c| c.contains("re-add") && c.contains("mise.lock")),
            "{cmds:?}"
        );
        assert!(
            cmds.iter()
                .any(|c| c.contains("re-add") && c.contains("flake.lock")),
            "{cmds:?}"
        );
    }

    #[test]
    fn run_argv_expands_home() {
        let tmp = tempfile::tempdir().unwrap();
        write_manifest_content(
            tmp.path(),
            r#"
[[steps]]
name = "home"
run = ["foo", "~/x/y"]
capture = []
"#,
        );
        let ex = Recording::new();
        run(
            &[],
            false,
            &ex,
            &FixedPaths(Some(tmp.path().to_owned())),
            None,
            &empty_engine(),
            no_config(),
            &StderrReporter,
        )
        .unwrap();
        let expected = format!("foo {}/x/y", dirs::home_dir().unwrap().display());
        assert_eq!(ex.cmds(), vec![expected]);
    }

    #[test]
    fn only_filter_runs_matching_step() {
        let tmp = tempfile::tempdir().unwrap();
        write_manifest(tmp.path());
        let ex = Recording::new();
        run(
            &["mise".to_owned()],
            false,
            &ex,
            &FixedPaths(Some(tmp.path().to_owned())),
            None,
            &empty_engine(),
            no_config(),
            &StderrReporter,
        )
        .unwrap();
        let cmds = ex.cmds();
        assert!(cmds.contains(&"mise upgrade --bump".to_owned()), "{cmds:?}");
        assert!(!cmds.iter().any(|c| c.contains("nix")), "{cmds:?}");
    }

    #[test]
    fn unknown_only_returns_error() {
        let tmp = tempfile::tempdir().unwrap();
        write_manifest(tmp.path());
        let ex = Recording::new();
        let result = run(
            &["unknown".to_owned()],
            false,
            &ex,
            &FixedPaths(Some(tmp.path().to_owned())),
            None,
            &empty_engine(),
            no_config(),
            &StderrReporter,
        );
        assert!(result.is_err(), "expected error for unknown step");
        assert!(ex.cmds().is_empty());
    }

    #[test]
    fn load_manifest_prefers_chezmoi_source() {
        let config = tempfile::tempdir().unwrap();
        let source = tempfile::tempdir().unwrap();
        write_manifest_content(
            config.path(),
            r#"
[[steps]]
name = "config"
run = ["config-tool"]
capture = []
"#,
        );
        write_manifest_content(
            source.path(),
            r#"
[[steps]]
name = "source"
run = ["source-tool"]
capture = []
"#,
        );
        let manifest = load_manifest(
            &FixedPaths(Some(config.path().to_owned())),
            Some(source.path()),
        )
        .unwrap();
        assert_eq!(manifest.steps[0].name, "source");
    }

    #[test]
    fn capture_runs_after_feature_hooks() {
        let tmp = tempfile::tempdir().unwrap();
        write_manifest_content(
            tmp.path(),
            r#"
[[steps]]
name = "mise"
run = ["mise", "upgrade", "--bump"]
capture = ["~/.pi/agent/settings.json"]
"#,
        );
        let cfg_path = tmp.path().join("config.toml");
        std::fs::write(
            &cfg_path,
            "schema_version=1\n[features.ai]\nenabled=true\n[dotfiles]\nbackend=\"chezmoi\"\n",
        )
        .unwrap();
        let cache_path = tmp.path().join("feature-meta.json");
        std::fs::write(
            &cache_path,
            r#"{"ai":{"description":"","category":"","updateHooks":[{"run":["pi","update","--extensions"],"onFailure":"warn"}]}}"#,
        )
        .unwrap();
        let engine = KaizenEngine::cache_only(Arc::new(StdFileSystem)).with_nix_cache(cache_path);
        let ex = Recording::new();
        run(
            &[],
            false,
            &ex,
            &FixedPaths(Some(tmp.path().to_owned())),
            None,
            &engine,
            &cfg_path,
            &StderrReporter,
        )
        .unwrap();
        let cmds = ex.cmds();
        let capture = format!(
            "chezmoi re-add {}/.pi/agent/settings.json",
            dirs::home_dir().unwrap().display()
        );
        assert_eq!(
            cmds,
            vec![
                "mise upgrade --bump".to_owned(),
                capture.clone(),
                "pi update --extensions".to_owned(),
                capture,
            ]
        );
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

    #[test]
    fn feature_hooks_skipped_when_only_filter_set() {
        let tmp = tempfile::tempdir().unwrap();
        write_manifest(tmp.path());
        let cfg_path = tmp.path().join("config.toml");
        std::fs::write(
            &cfg_path,
            "schema_version=1\n[features.ai]\nenabled=true\n[dotfiles]\nbackend=\"chezmoi\"\n",
        )
        .unwrap();
        let cache_path = tmp.path().join("feature-meta.json");
        std::fs::write(
            &cache_path,
            r#"{"ai":{"description":"","category":"","updateHooks":[{"run":["pi","update","--extensions"],"onFailure":"warn"}]}}"#,
        )
        .unwrap();
        let engine = KaizenEngine::cache_only(Arc::new(StdFileSystem)).with_nix_cache(cache_path);
        let ex = Recording::new();
        run(
            &["mise".to_owned()],
            false,
            &ex,
            &FixedPaths(Some(tmp.path().to_owned())),
            None,
            &engine,
            &cfg_path,
            &StderrReporter,
        )
        .unwrap();
        assert!(
            !ex.cmds().iter().any(|c| c.contains("pi")),
            "{:?}",
            ex.cmds()
        );
    }
}
