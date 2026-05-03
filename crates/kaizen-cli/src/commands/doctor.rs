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

    report_config(engine, config_path);

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

fn report_config(engine: &KaizenEngine, config_path: &Path) {
    output::header("Config");

    if !config_path.exists() {
        output::item_err(&format!(
            "{} not found  (run: kaizen setup)",
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
