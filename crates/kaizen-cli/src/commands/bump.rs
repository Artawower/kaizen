use anyhow::Result;
use kaizen_core::{PathProvider, ProcessCommand, ProcessExecutor, ProgressReporter, TargetOs};
use owo_colors::OwoColorize;

use crate::output;

pub fn run(
    only_nix: bool,
    only_mise: bool,
    dry_run: bool,
    executor: &dyn ProcessExecutor,
    paths: &dyn PathProvider,
    reporter: &dyn ProgressReporter,
) -> Result<()> {
    output::page_header(if dry_run { "bump  (dry-run)" } else { "bump" });

    let all = !only_nix && !only_mise;
    let bump_nix = all || only_nix;
    let bump_mise = all || only_mise;

    let config_dir = paths
        .config_dir()
        .ok_or_else(|| anyhow::anyhow!("cannot determine config directory"))?;

    if bump_nix {
        run_nix_bump(&config_dir, dry_run, executor, reporter)?;
    }
    if bump_mise {
        run_mise_bump(&config_dir, dry_run, executor, reporter)?;
    }

    if !dry_run {
        println!();
        output::item_ok("bump complete — commit the updated lock files");
    }
    Ok(())
}

fn run_nix_bump(
    config_dir: &std::path::Path,
    dry_run: bool,
    executor: &dyn ProcessExecutor,
    reporter: &dyn ProgressReporter,
) -> Result<()> {
    let flake_dir = config_dir.join("nix");
    let flake_lock = flake_dir.join("flake.lock");
    let flake_arg = flake_dir.to_string_lossy().into_owned();

    output::header("nix");

    if dry_run {
        println!(
            "  {}  nix flake update --flake {}",
            "→".dimmed(),
            flake_arg.dimmed()
        );
        println!("  {}  <rebuild nix>", "→".dimmed());
        println!(
            "  {}  chezmoi re-add {}",
            "→".dimmed(),
            flake_lock.display().to_string().dimmed()
        );
        return Ok(());
    }

    reporter.step("→ nix flake update");
    executor.execute(ProcessCommand::run(
        "nix",
        ["flake", "update", "--flake", &flake_arg],
    ))?;

    rebuild_nix(&flake_arg, executor, reporter)?;

    reporter.step("→ chezmoi re-add flake.lock");
    executor.execute(ProcessCommand::run(
        "chezmoi",
        ["re-add", &flake_lock.to_string_lossy()],
    ))?;

    output::item_ok("nix flake inputs bumped");
    Ok(())
}

fn rebuild_nix(
    flake_arg: &str,
    executor: &dyn ProcessExecutor,
    reporter: &dyn ProgressReporter,
) -> Result<()> {
    let os = TargetOs::detect();
    if os == TargetOs::Darwin {
        reporter.step("→ darwin-rebuild switch");
        executor.execute(
            ProcessCommand::run("darwin-rebuild", ["switch", "--flake", flake_arg]).sudo(),
        )?;
    }
    reporter.step("→ home-manager switch");
    let out = executor.execute(ProcessCommand::run("id", ["-un"]).capturing())?;
    let user = out.stdout.trim().to_owned();
    if user.is_empty() {
        anyhow::bail!("could not determine current user (id -un returned empty output)");
    }
    let host = if os == TargetOs::Darwin {
        "mac"
    } else {
        "linux"
    };
    let flake_target = format!("{flake_arg}#{user}@{host}");
    executor.execute(ProcessCommand::run(
        "home-manager",
        ["switch", "--flake", &flake_target, "--impure"],
    ))?;
    Ok(())
}

fn run_mise_bump(
    config_dir: &std::path::Path,
    dry_run: bool,
    executor: &dyn ProcessExecutor,
    reporter: &dyn ProgressReporter,
) -> Result<()> {
    let mise_lock = config_dir.join("mise.lock");

    output::header("mise");

    if dry_run {
        println!("  {}  mise upgrade --bump", "→".dimmed());
        println!(
            "  {}  chezmoi re-add {}",
            "→".dimmed(),
            mise_lock.display().to_string().dimmed()
        );
        return Ok(());
    }

    reporter.step("→ mise upgrade --bump");
    executor.execute(ProcessCommand::run("mise", ["upgrade", "--bump"]))?;

    reporter.step("→ chezmoi re-add mise.lock");
    executor.execute(ProcessCommand::run(
        "chezmoi",
        ["re-add", &mise_lock.to_string_lossy()],
    ))?;

    output::item_ok("mise tools bumped");
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::Mutex;

    use kaizen_core::{KaizenError, PathProvider, ProcessCommand, ProcessExecutor, ProcessOutput};

    use super::*;
    use crate::reporter::StderrReporter;

    struct FixedPathProvider {
        config: Option<PathBuf>,
    }

    impl PathProvider for FixedPathProvider {
        fn home_dir(&self) -> Option<PathBuf> {
            None
        }
        fn config_dir(&self) -> Option<PathBuf> {
            self.config.clone()
        }
        fn is_tool_available(&self, _: &str) -> bool {
            false
        }
    }

    struct RecordingExecutor {
        calls: Mutex<Vec<String>>,
        /// Canned stdout response for commands that need it (e.g. `id -un`).
        stdout_for: Option<(&'static str, &'static str)>,
    }

    impl RecordingExecutor {
        fn new() -> Self {
            Self {
                calls: Mutex::new(vec![]),
                stdout_for: None,
            }
        }

        fn with_stdout(bin: &'static str, stdout: &'static str) -> Self {
            Self {
                calls: Mutex::new(vec![]),
                stdout_for: Some((bin, stdout)),
            }
        }

        fn commands(&self) -> Vec<String> {
            self.calls.lock().unwrap().clone()
        }
    }

    impl ProcessExecutor for RecordingExecutor {
        fn execute(&self, cmd: ProcessCommand) -> Result<ProcessOutput, KaizenError> {
            let entry = format!("{} {}", cmd.bin, cmd.args.join(" "))
                .trim()
                .to_owned();
            self.calls.lock().unwrap().push(entry);
            let stdout = self
                .stdout_for
                .filter(|(bin, _)| *bin == cmd.bin)
                .map(|(_, out)| out.to_owned())
                .unwrap_or_default();
            Ok(ProcessOutput { stdout })
        }
    }

    fn paths(config: &str) -> FixedPathProvider {
        FixedPathProvider {
            config: Some(PathBuf::from(config)),
        }
    }

    #[test]
    fn dry_run_does_not_call_executor() {
        let ex = RecordingExecutor::new();
        run(false, false, true, &ex, &paths("/config"), &StderrReporter).unwrap();
        assert!(ex.commands().is_empty());
    }

    #[test]
    fn only_nix_dry_run_skips_mise() {
        let ex = RecordingExecutor::new();
        run(true, false, true, &ex, &paths("/config"), &StderrReporter).unwrap();
        assert!(ex.commands().is_empty());
    }

    #[test]
    fn only_mise_dry_run_skips_nix() {
        let ex = RecordingExecutor::new();
        run(false, true, true, &ex, &paths("/config"), &StderrReporter).unwrap();
        assert!(ex.commands().is_empty());
    }

    #[test]
    fn mise_bump_runs_correct_commands() {
        let ex = RecordingExecutor::new();
        run(false, true, false, &ex, &paths("/config"), &StderrReporter).unwrap();
        let cmds = ex.commands();
        assert!(
            cmds.contains(&"mise upgrade --bump".to_owned()),
            "expected mise upgrade --bump, got {cmds:?}"
        );
        assert!(
            cmds.iter()
                .any(|c| c.starts_with("chezmoi re-add") && c.contains("mise.lock")),
            "expected chezmoi re-add mise.lock, got {cmds:?}"
        );
    }

    #[test]
    fn nix_bump_runs_correct_commands() {
        // Provide a canned user for `id -un` so the test doesn't spawn a real process.
        let ex = RecordingExecutor::with_stdout("id", "testuser\n");
        run(true, false, false, &ex, &paths("/config"), &StderrReporter).unwrap();
        let cmds = ex.commands();
        assert!(
            cmds.iter().any(|c| c.starts_with("nix flake update")),
            "expected nix flake update, got {cmds:?}"
        );
        assert!(
            cmds.iter().any(|c| c.starts_with("home-manager switch")),
            "expected home-manager switch, got {cmds:?}"
        );
        assert!(
            cmds.iter()
                .any(|c| c.starts_with("chezmoi re-add") && c.contains("flake.lock")),
            "expected chezmoi re-add flake.lock, got {cmds:?}"
        );
    }
}
