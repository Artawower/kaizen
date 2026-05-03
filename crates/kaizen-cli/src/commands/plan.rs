use std::path::Path;

use anyhow::Result;
use kaizen_core::{KaizenEngine, TargetOs};
use owo_colors::OwoColorize;

use crate::output;

pub fn run(engine: &KaizenEngine, config_path: &Path, json: bool) -> Result<()> {
    let config = engine.load_config(config_path)?;
    let plan = engine.build_workflow_plan(&config, TargetOs::detect())?;

    if json {
        println!("{}", serde_json::to_string_pretty(&plan)?);
        return Ok(());
    }

    output::page_header(&format!("plan  ·  {}", plan.target_os.dimmed()));

    output::header("Features");
    for (name, selection) in &config.features {
        output::feature_row(name, selection.enabled, &selection.disabled_atoms);
    }

    if !plan.install_plan.programs.is_empty() {
        output::header("Install via upt");
        for chunk in plan.install_plan.programs.chunks(3) {
            let row: Vec<String> = chunk.iter().map(|p| format!("{p:<20}")).collect();
            println!("  {}", row.join(""));
        }
    }

    if !plan.install_plan.mise_tools.is_empty() {
        output::header("Dev tools via mise");
        for (name, version) in &plan.install_plan.mise_tools {
            output::kv(name, version);
        }
    }

    output::header("Config");
    output::kv("backend", &plan.config_plan.backend);
    if let Some(layout) = &plan.config_plan.settings.layout {
        output::kv("layout", layout);
    }
    if let Some(source) = &plan.config_plan.dotfiles_source {
        output::kv("dotfiles source", source);
    }

    if !plan.warnings.is_empty() {
        output::header("Warnings");
        for w in &plan.warnings {
            output::item_warn(w);
        }
    }

    println!();
    Ok(())
}
