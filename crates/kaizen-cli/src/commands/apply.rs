use std::path::Path;

use anyhow::Result;
use kaizen_core::{KaizenEngine, TargetOs};
use owo_colors::OwoColorize;

use crate::{ensure, output};

pub fn run(engine: &KaizenEngine, config_path: &Path, dry_run: bool) -> Result<()> {
    output::page_header(if dry_run { "apply  (dry-run)" } else { "apply" });

    let config = engine.load_config(config_path)?;
    output::warn_if_schema_outdated(&config);

    let plan = engine.build_workflow_plan(&config, TargetOs::detect())?;
    let (source_dir, is_fallback) = kaizen_core::chezmoi::source_path(&plan.config_plan)?;
    let data_path = source_dir.join(".chezmoidata.toml");
    let content = kaizen_core::chezmoi::generate_chezmoidata(&plan.config_plan)?;

    output::header("Chezmoi data");
    output::kv("source dir", &source_dir.display().to_string());
    output::kv("data file", &data_path.display().to_string());
    println!();

    if dry_run {
        if is_fallback {
            output::item_warn("chezmoi source dir not confirmed — run 'chezmoi init' first");
        }
        println!("{}", "  --- .chezmoidata.toml ---".dimmed());
        for line in content.lines() {
            println!("  {}", line.dimmed());
        }
        println!();
        println!("  Run without --dry-run to write.");
        return Ok(());
    }

    ensure::require(&[&ensure::CHEZMOI])?;

    if is_fallback {
        anyhow::bail!("chezmoi source directory not confirmed — run 'chezmoi init' first");
    }

    if let Some(parent) = data_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&data_path, &content)?;
    output::item_ok(&format!("wrote {}", data_path.display()));
    println!();
    println!("  Next: {}  apply", "chezmoi".bold().cyan());
    Ok(())
}
