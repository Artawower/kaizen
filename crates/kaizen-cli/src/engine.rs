use std::path::PathBuf;
use std::sync::Arc;

use kaizen_core::{manifest, KaizenEngine, PathProvider as _};

use crate::{filesystem::StdFileSystem, paths::StdPathProvider, reporter::StderrReporter};

fn nix_cache_path() -> Option<PathBuf> {
    StdPathProvider
        .config_dir()
        .map(|d| d.join("kaizen").join("feature-meta.json"))
}

/// Resolve features directory; when `use_cache` is true and the directory
/// is missing, return the expected path without failing — the engine will
/// use the Nix cache instead of reading TOML files.
pub fn resolve_features_dir_lenient(
    explicit: Option<PathBuf>,
    reporter: &StderrReporter,
    use_cache: bool,
) -> PathBuf {
    let fallback = || PathBuf::from(manifest::KAIZEN_DIR).join(manifest::FEATURES_SUBDIR);
    if use_cache && explicit.is_none() {
        return kaizen_core::resolve_features_dir(
            None,
            reporter,
            &crate::chezmoi::StdChezmoiClient,
            &StdFileSystem,
        )
        .unwrap_or_else(|_| fallback());
    }
    kaizen_core::resolve_features_dir(
        explicit,
        reporter,
        &crate::chezmoi::StdChezmoiClient,
        &StdFileSystem,
    )
    .unwrap_or_else(|_| fallback())
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
