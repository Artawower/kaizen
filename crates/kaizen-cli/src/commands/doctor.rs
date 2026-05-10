use std::path::Path;

use anyhow::Result;
use kaizen_core::KaizenEngine;
use owo_colors::OwoColorize;

use crate::ensure::Tool;
use crate::{ensure, output};

pub fn run(engine: &KaizenEngine, config_path: &Path) -> Result<()> {
    output::page_header("doctor");

    output::header("System");
    output::kv("OS", &kaizen_core::TargetOs::detect().to_string());
    output::kv("arch", std::env::consts::ARCH);

    output::header("Tools");
    for tool in ensure::ALL {
        report_tool(tool);
    }

    report_nix_tools();
    report_config(engine, config_path);
    report_version();

    output::header("Features");
    match engine.list_features() {
        Ok(names) if !names.is_empty() => {
            output::item_ok(&format!("{} feature(s) available", names.len()))
        }
        Ok(_) => output::item_warn("features dir is empty"),
        Err(e) => output::item_err(&e.to_string()),
    }

    println!();
    Ok(())
}

fn report_nix_tools() {
    let any_nix = ensure::NIX_TOOLS
        .iter()
        .any(|t| which::which(t.name).is_ok());

    if !any_nix {
        return;
    }

    output::header("Nix");
    for tool in ensure::NIX_TOOLS {
        report_tool(tool);
    }
}

fn report_tool(tool: &Tool) {
    match which::which(tool.name) {
        Ok(path) => output::item_ok(&format!(
            "{:<12} {}",
            tool.name,
            path.display().to_string().dimmed()
        )),
        Err(_) => output::item_err(&format!(
            "{:<12} not found  ({})",
            tool.name,
            tool.install_hint.dimmed()
        )),
    }
}

fn report_version() {
    use super::self_update::{fetch_latest, versions_equal};

    output::header("Version");
    let current = env!("CARGO_PKG_VERSION");
    output::kv("installed", current);

    match fetch_latest() {
        Ok(latest) if versions_equal(current, &latest) => {
            output::item_ok("up to date");
        }
        Ok(latest) => {
            output::item_warn(&format!(
                "update available: {current} → {}  (run: kaizen self-update)",
                latest.green()
            ));
        }
        Err(_) => {
            output::item_warn("could not check for updates (offline?)");
        }
    }
}

fn report_config(engine: &KaizenEngine, config_path: &Path) {
    output::header("Config");

    if !config_path.exists() {
        output::item_err(&format!(
            "{} not found  (run: kaizen install)",
            config_path.display()
        ));
        return;
    }

    output::item_ok(&format!("{}", config_path.display()));

    match engine.load_config(config_path) {
        Ok(cfg) => {
            output::warn_if_schema_outdated(&cfg);
            let n = cfg.features.values().filter(|f| f.enabled).count();
            output::kv("  enabled features", &n.to_string());
        }
        Err(e) => output::item_err(&format!("parse error: {e}")),
    }
}
