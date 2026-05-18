use std::path::PathBuf;
use std::sync::Arc;

use kaizen_core::{KaizenEngine, PathProvider as _};

use crate::{chezmoi::StdChezmoiClient, filesystem::StdFileSystem, paths::StdPathProvider};
use kaizen_core::chezmoi_client::ChezmoiClient as _;

fn nix_cache_path() -> Option<PathBuf> {
    StdPathProvider
        .config_dir()
        .map(|d| d.join("kaizen").join("feature-meta.json"))
}

fn data_toml_path() -> Option<PathBuf> {
    StdPathProvider
        .config_dir()
        .map(|d| d.join("kaizen").join("data.toml"))
}

/// Build an engine backed by an explicit features directory.
/// The Nix cache is attached when `use_nix_cache` is true.
pub fn build(features_dir: PathBuf, use_nix_cache: bool) -> KaizenEngine {
    let engine = KaizenEngine::new(features_dir, Arc::new(StdFileSystem));
    attach_paths(engine, use_nix_cache)
}

/// Build an engine that reads exclusively from the Nix feature cache.
/// Falls back gracefully — the engine returns `FeaturesDirNotFound` only
/// when a feature listing is actually needed and the cache is absent.
pub fn build_cache_only() -> KaizenEngine {
    attach_paths(KaizenEngine::cache_only(Arc::new(StdFileSystem)), true)
}

fn variants_dir() -> Option<PathBuf> {
    // Variants live at <chezmoi-source-parent>/features/
    // e.g. ~/.local/share/chezmoi/features/ (one level above dotfiles/)
    let source = StdChezmoiClient.source_path().ok()??;
    let candidate = source.parent()?.join("features");
    candidate.exists().then_some(candidate)
}

fn attach_paths(engine: KaizenEngine, use_nix_cache: bool) -> KaizenEngine {
    let engine = if use_nix_cache {
        match nix_cache_path() {
            Some(p) => engine.with_nix_cache(p),
            None => engine,
        }
    } else {
        engine
    };
    let engine = match variants_dir() {
        Some(p) => engine.with_variants_dir(p),
        None => engine,
    };
    match data_toml_path() {
        Some(p) => engine.with_data_toml_path(p),
        None => engine,
    }
}
