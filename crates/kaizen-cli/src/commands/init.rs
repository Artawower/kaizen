use std::path::Path;

use anyhow::Result;
use kaizen_core::KaizenEngine;

use crate::{commands, output};

/// Full first-time setup: wizard + sync.
///
/// If config already exists, skips the wizard and goes straight to sync.
pub fn run(
    engine: &KaizenEngine,
    features_dir: Option<&Path>,
    config_path: &Path,
    dry_run: bool,
) -> Result<()> {
    if config_path.exists() {
        output::item_ok(&format!(
            "config found at {} — skipping setup",
            config_path.display()
        ));
    } else {
        println!();
        output::page_header("init — setup");
        commands::setup::run(features_dir, config_path)?;
        println!();
    }

    commands::sync::run(engine, config_path, dry_run)
}
