use std::path::Path;

use anyhow::Result;
use kaizen_core::{detect_backend, CleanOpts, KaizenEngine, TargetOs};
use owo_colors::OwoColorize;

use crate::output;

pub fn run(engine: &KaizenEngine, config_path: &Path, dry_run: bool) -> Result<()> {
    output::page_header(if dry_run { "clean  (dry-run)" } else { "clean" });

    let config = engine.load_config(config_path)?;
    let os = TargetOs::detect();
    let plan = engine.build_workflow_plan(&config, os.clone())?;
    let backend = detect_backend(os);

    output::kv("backend", backend.id());
    println!();

    if dry_run {
        let preview = backend.preview(&plan);
        let clean_hint = format!(
            "nix-collect-garbage --delete-older-than 7d\n  {}  OS cache clean\n  {}  docker system prune -f",
            "→".dimmed(),
            "→".dimmed()
        );
        println!("  {}  {}", "→".dimmed(), clean_hint.dimmed());
        println!();
        println!("  Run without --dry-run to clean.");
        let _ = preview;
        return Ok(());
    }

    let report = backend.clean(&CleanOpts { dry_run: false })?;

    for step in &report.steps {
        output::item_ok(step);
    }
    if let Some(freed) = report.freed_bytes {
        println!();
        output::item_ok(&format!("freed {:.1} GB", freed as f64 / 1_073_741_824.0));
    }

    println!();
    output::item_ok("clean complete");
    Ok(())
}
