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

    let report = backend.clean(&CleanOpts { dry_run })?;

    if dry_run {
        output::header("would run");
        for step in &report.steps {
            println!("  {}  {}", "→".dimmed(), step.dimmed());
        }
        println!();
        println!("  Run without --dry-run to clean.");
        let _ = plan;
        return Ok(());
    }

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
