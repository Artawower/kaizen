use anyhow::Result;
use kaizen_core::HookRunner;
use owo_colors::OwoColorize;

use crate::output;

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
