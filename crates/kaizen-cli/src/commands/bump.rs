use anyhow::{Context, Result};
use kaizen_core::{
    bump::{BumpManifest, BUMP_MANIFEST_FILE},
    PathProvider, ProcessCommand, ProcessExecutor, ProgressReporter,
};
use owo_colors::OwoColorize;

use crate::output;

pub fn run(
    only: &[String],
    dry_run: bool,
    executor: &dyn ProcessExecutor,
    paths: &dyn PathProvider,
    reporter: &dyn ProgressReporter,
) -> Result<()> {
    output::page_header(if dry_run { "bump  (dry-run)" } else { "bump" });

    let manifest = load_manifest(paths)?;
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

    for step in steps {
        output::header(&step.name);

        let (bin, args) = step
            .run
            .split_first()
            .with_context(|| format!("step '{}': run list is empty", step.name))?;

        if dry_run {
            println!("  {}  {}", "→".dimmed(), step.run.join(" ").dimmed());
            for path in &step.capture {
                println!("  {}  chezmoi re-add {}", "→".dimmed(), path.dimmed());
            }
            continue;
        }

        reporter.step(&format!("→ {}", step.run.join(" ")));
        executor
            .execute(ProcessCommand::run(bin, args.iter().map(String::as_str)))
            .with_context(|| format!("step '{}': command failed", step.name))?;

        for raw_path in &step.capture {
            let expanded = expand_home(raw_path, home.as_deref());
            reporter.step(&format!("→ chezmoi re-add {expanded}"));
            executor
                .execute(ProcessCommand::run("chezmoi", ["re-add", &expanded]))
                .with_context(|| {
                    format!("step '{}': chezmoi re-add {expanded} failed", step.name)
                })?;
        }

        output::item_ok(&format!("{} done", step.name));
    }

    if !dry_run {
        println!();
        output::item_ok("bump complete — commit the updated lock files");
    }
    Ok(())
}

fn load_manifest(paths: &dyn PathProvider) -> Result<BumpManifest> {
    let Some(config_dir) = paths.config_dir() else {
        return Ok(BumpManifest::default());
    };
    let path = config_dir.join("kaizen").join(BUMP_MANIFEST_FILE);
    if !path.exists() {
        return Ok(BumpManifest::default());
    }
    let content = std::fs::read_to_string(&path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    BumpManifest::from_toml(&content).with_context(|| format!("failed to parse {}", path.display()))
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

    use kaizen_core::{KaizenError, PathProvider, ProcessCommand, ProcessExecutor, ProcessOutput};

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
            })
        }
    }

    fn write_manifest(dir: &std::path::Path) {
        let kaizen_dir = dir.join("kaizen");
        std::fs::create_dir_all(&kaizen_dir).unwrap();
        std::fs::write(kaizen_dir.join(BUMP_MANIFEST_FILE), SAMPLE_MANIFEST).unwrap();
    }

    #[test]
    fn dry_run_no_config_dir_executes_nothing() {
        let ex = Recording::new();
        run(&[], true, &ex, &FixedPaths(None), &StderrReporter).unwrap();
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
    fn only_filter_runs_matching_step() {
        let tmp = tempfile::tempdir().unwrap();
        write_manifest(tmp.path());
        let ex = Recording::new();
        run(
            &["mise".to_owned()],
            false,
            &ex,
            &FixedPaths(Some(tmp.path().to_owned())),
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
            &StderrReporter,
        );
        assert!(result.is_err(), "expected error for unknown step");
        assert!(ex.cmds().is_empty());
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
