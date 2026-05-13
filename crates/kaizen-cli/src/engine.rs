use std::path::PathBuf;
use std::sync::Arc;

use kaizen_core::{KaizenEngine, PathProvider as _};

use crate::{filesystem::StdFileSystem, paths::StdPathProvider};

fn nix_cache_path() -> Option<PathBuf> {
    StdPathProvider
        .config_dir()
        .map(|d| d.join("kaizen").join("feature-meta.json"))
}

/// Build an engine backed by an explicit features directory.
/// The Nix cache is attached when `use_nix_cache` is true.
pub fn build(features_dir: PathBuf, use_nix_cache: bool) -> KaizenEngine {
    let engine = KaizenEngine::new(features_dir, Arc::new(StdFileSystem));
    attach_cache(engine, use_nix_cache)
}

/// Build an engine that reads exclusively from the Nix feature cache.
/// Falls back gracefully — the engine returns `FeaturesDirNotFound` only
/// when a feature listing is actually needed and the cache is absent.
pub fn build_cache_only() -> KaizenEngine {
    attach_cache(KaizenEngine::cache_only(Arc::new(StdFileSystem)), true)
}

fn attach_cache(engine: KaizenEngine, use_nix_cache: bool) -> KaizenEngine {
    if !use_nix_cache {
        return engine;
    }
    match nix_cache_path() {
        Some(p) => engine.with_nix_cache(p),
        None => engine,
    }
}
