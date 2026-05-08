use std::path::Path;

use anyhow::Result;
use kaizen_core::{detect_backend, KaizenEngine, SyncOpts, TargetOs};

use crate::output;

pub fn run(engine: &KaizenEngine, config_path: &Path, dry_run: bool) -> Result<()> {
    output::page_header(if dry_run { "sync  (dry-run)" } else { "sync" });

    let config = engine.load_config(config_path)?;
    output::warn_if_schema_outdated(&config);

    let os = TargetOs::detect();
    let plan = engine.build_workflow_plan(&config, os.clone())?;
    let backend = detect_backend(os);

    output::kv("backend", backend.id());
    println!();

    if dry_run {
        let preview = backend.preview(&plan);
        output::header("steps");
        for step in &preview.steps {
            println!("  {:<25} {}", step.label, step.command);
        }
        println!();
        println!("  Run without --dry-run to apply.");
        return Ok(());
    }

    backend.sync(&plan, &SyncOpts { dry_run: false })?;

    println!();
    output::item_ok("sync complete");
    Ok(())
}
