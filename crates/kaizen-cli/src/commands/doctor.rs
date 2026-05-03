use std::path::Path;

use anyhow::Result;
use kaizen_core::KaizenEngine;
use owo_colors::OwoColorize;
use which::which;

use crate::output;

const TOOLS: &[(&str, &str)] = &[
    ("upt", "https://github.com/sigoden/upt"),
    ("chezmoi", "https://www.chezmoi.io"),
    ("mise", "https://mise.jdx.dev"),
];

pub fn run(engine: &KaizenEngine, config_path: &Path) -> Result<()> {
    println!("\n{}  doctor", "kaizen".bold().green());
    println!("{}", "═".repeat(44).dimmed());

    output::header("System");
    output::kv("OS", &kaizen_core::TargetOs::detect().to_string());
    output::kv("arch", std::env::consts::ARCH);

    output::header("Tools");
    for (tool, hint) in TOOLS {
        match which(tool) {
            Ok(path) => output::item_ok(&format!(
                "{tool:<12} {}",
                path.display().to_string().dimmed()
            )),
            Err(_) => output::item_err(&format!("{tool:<12} not found  ({})", hint.dimmed())),
        }
    }

    output::header("Config");
    if config_path.exists() {
        output::item_ok(&format!("{}", config_path.display()));
        match engine.load_config(config_path) {
            Ok(cfg) => {
                let n = cfg.features.values().filter(|f| f.enabled).count();
                output::kv("  enabled features", &n.to_string());
            }
            Err(e) => output::item_err(&format!("parse error: {e}")),
        }
    } else {
        output::item_err(&format!(
            "{} not found  (pass --config <path> or create it)",
            config_path.display()
        ));
    }

    output::header("Features");
    match engine.list_features() {
        Ok(names) if !names.is_empty() => {
            output::item_ok(&format!("{} feature(s) available", names.len()));
        }
        Ok(_) => output::item_warn("features dir is empty"),
        Err(e) => output::item_err(&e.to_string()),
    }

    println!();
    Ok(())
}
