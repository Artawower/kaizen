use std::path::Path;

use anyhow::Result;
use kaizen_core::{
    detect_backend, KaizenEngine, ShellHookRunner, TargetOs, UpdateOpts, UserConfig,
};
use owo_colors::OwoColorize;

use crate::{hooks, output, selector};

pub fn run(
    engine: &KaizenEngine,
    config_path: &Path,
    dry_run: bool,
    update_flake: bool,
    features: Vec<String>,
    interactive: bool,
) -> Result<()> {
    output::page_header(if dry_run {
        "update  (dry-run)"
    } else {
        "update"
    });

    let config = engine.load_config(config_path)?;
    output::warn_if_schema_outdated(&config);

    let selected = resolve_features(&config, features, interactive)?;
    let Some(selected) = selected else {
        return Ok(());
    };
    if selected.is_empty() {
        output::item_warn("no enabled features — nothing to update");
        return Ok(());
    }

    let mut filtered = config.clone();
    for (name, sel) in filtered.features.iter_mut() {
        if !selected.contains(name) {
            sel.enabled = false;
        }
    }

    let os = TargetOs::detect();
    let plan = engine.build_workflow_plan(&filtered, os.clone())?;
    let backend = detect_backend(os);

    output::kv("backend", backend.id());
    if update_flake {
        output::kv("flake update", "yes");
    }
    println!();

    if dry_run {
        println!(
            "  {}  would run update for {} feature(s)",
            "→".dimmed(),
            selected.len()
        );
        println!();
        println!("  Run without --dry-run to apply.");
        return Ok(());
    }

    let report = backend.update(
        &plan,
        &UpdateOpts {
            dry_run,
            update_flake,
        },
    )?;

    for w in &report.warnings {
        output::item_warn(w);
    }

    hooks::run(&plan.hook_plan.post_update, dry_run, &ShellHookRunner)?;

    println!();
    output::item_ok(&format!("updated {} feature(s)", selected.len()));
    Ok(())
}

fn resolve_features(
    config: &UserConfig,
    features: Vec<String>,
    interactive: bool,
) -> Result<Option<Vec<String>>> {
    if interactive {
        let items: Vec<selector::Item> = config
            .features
            .iter()
            .filter(|(_, s)| s.enabled)
            .map(|(name, _)| selector::Item {
                name: name.clone(),
                desc: None,
                selected: true,
            })
            .collect();
        return selector::multi_select("Select features to update", items);
    }
    if !features.is_empty() {
        return Ok(Some(features));
    }
    Ok(Some(
        config
            .features
            .iter()
            .filter(|(_, s)| s.enabled)
            .map(|(k, _)| k.clone())
            .collect(),
    ))
}
