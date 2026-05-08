use std::path::Path;

use anyhow::Result;
use kaizen_core::{detect_backend, KaizenEngine, SyncOpts, TargetOs};
use owo_colors::OwoColorize;

use crate::output;

pub fn run(engine: &KaizenEngine, config_path: &Path, dry_run: bool) -> Result<()> {
    output::page_header(if dry_run { "apply  (dry-run)" } else { "apply" });

    let config = engine.load_config(config_path)?;
    output::warn_if_schema_outdated(&config);

    let os = TargetOs::detect();
    let plan = engine.build_workflow_plan(&config, os.clone())?;
    let backend = detect_backend(os);

    output::kv("backend", backend.id());
    println!();

    let opts = SyncOpts { dry_run };

    if dry_run {
        let preview = backend.apply_preview(&plan);
        output::header("steps");
        for step in &preview.steps {
            println!("  {}  {}", "→".dimmed(), step.command.dimmed());
        }
        println!();
        println!("  Run without --dry-run to apply.");
        return Ok(());
    }

    let report = backend.apply(&plan, &opts)?;
    if let Some(path) = &report.data_path {
        output::item_ok(&format!("wrote {}", path.display()));
    }
    output::item_ok("chezmoi apply done");

    backend.post_apply(&opts)?;
    output::item_ok("mise install done");

    println!();
    output::item_ok("apply complete");
    Ok(())
}
