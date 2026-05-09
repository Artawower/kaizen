use std::path::Path;

use anyhow::Result;
use kaizen_core::KaizenEngine;

use kaizen_core::ChezmoiClient;

use crate::{chezmoi::StdChezmoiClient, commands, output};

/// First-time machine install: configure if needed, then sync.
///
/// Runs the configure wizard when EITHER:
/// - config does not exist yet, OR
/// - chezmoi source is not initialized (dotfiles not cloned)
///
/// This ensures that on a fresh machine the user is always asked for
/// the dotfiles URL even if a stale config already exists.
pub fn run(
    engine: &KaizenEngine,
    features_dir: Option<&Path>,
    config_path: &Path,
    dry_run: bool,
) -> Result<()> {
    let config_exists = config_path.exists();
    let chezmoi_ready = StdChezmoiClient.source_path().unwrap_or(None).is_some();

    let need_configure = !config_exists || !chezmoi_ready;

    if need_configure {
        if config_exists && !chezmoi_ready {
            output::item_warn("dotfiles not cloned yet — running configure to initialize chezmoi");
        }
        println!();
        output::page_header("install — configure");
        commands::configure::run(features_dir, config_path)?;
        println!();
    } else {
        output::item_ok("config and dotfiles found — skipping configure");
    }

    commands::sync::run(engine, config_path, dry_run)
}
