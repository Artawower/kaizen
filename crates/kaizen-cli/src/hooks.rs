use anyhow::Result;
use kaizen_core::{HookRunner, KaizenError};
use owo_colors::OwoColorize;

use crate::output;

/// Concrete shell-based hook runner. Lives in CLI, not in core, because it spawns processes.
pub struct ShellHookRunner;

impl HookRunner for ShellHookRunner {
    fn run(&self, commands: &[String]) -> Result<(), KaizenError> {
        for cmd in commands {
            let status = std::process::Command::new("sh")
                .arg("-c")
                .arg(cmd)
                .status()
                .map_err(|e| KaizenError::HookFailed {
                    command: cmd.clone(),
                    reason: e.to_string(),
                })?;

            if !status.success() {
                return Err(KaizenError::HookFailed {
                    command: cmd.clone(),
                    reason: format!(
                        "exited with {}",
                        status
                            .code()
                            .map(|c| c.to_string())
                            .unwrap_or_else(|| "signal".to_owned())
                    ),
                });
            }
        }
        Ok(())
    }
}

pub fn run(commands: &[String], dry_run: bool, runner: &dyn HookRunner) -> Result<()> {
    if commands.is_empty() {
        return Ok(());
    }
    output::header(&format!("Hooks ({})", commands.len()));
    for cmd in commands {
        println!("  {}  {}", "$".dimmed(), cmd);
    }
    if dry_run {
        return Ok(());
    }
    println!();
    runner.run(commands)?;
    output::item_ok("hooks done");
    Ok(())
}
