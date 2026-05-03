use std::path::Path;

use anyhow::Result;
use kaizen_core::KaizenEngine;

use crate::output;

pub fn run(engine: &KaizenEngine, config_path: &Path, dry_run: bool) -> Result<()> {
    super::install::run(engine, config_path, dry_run)?;
    println!();
    super::apply::run(engine, config_path, dry_run)?;

    if !dry_run {
        println!();
        output::item_ok("sync complete");
    }
    Ok(())
}
