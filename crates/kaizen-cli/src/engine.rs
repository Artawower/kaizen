use std::path::PathBuf;
use std::sync::Arc;

use kaizen_core::{KaizenEngine, PathProvider as _};

use crate::{filesystem::StdFileSystem, paths::StdPathProvider};

fn nix_cache_path() -> Option<PathBuf> {
    StdPathProvider
        .config_dir()
        .map(|d| d.join("kaizen").join("feature-meta.json"))
}

/// Build a `KaizenEngine` for the given features directory.
///
/// The Nix-generated `feature-meta.json` cache is attached only when
/// `use_nix_cache` is true — i.e. when the features directory was resolved
/// automatically from the chezmoi source, not explicitly provided by the user.
/// This prevents a stale or wrong-source cache from overriding an explicit
/// `--features-dir` or custom dotfiles source.
pub fn build(features_dir: PathBuf, use_nix_cache: bool) -> KaizenEngine {
    let engine = KaizenEngine::new(features_dir, Arc::new(StdFileSystem));
    if !use_nix_cache {
        return engine;
    }
    match nix_cache_path() {
        Some(p) => engine.with_nix_cache(p),
        None => engine,
    }
}
