use std::path::{Path, PathBuf};

use crate::{chezmoi, manifest, KaizenError};

/// Outcome of inspecting the current chezmoi source state before bootstrapping.
pub enum BootstrapStatus {
    /// Source already exists and its remote matches the requested URL. No action needed.
    AlreadyUpToDate(PathBuf),
    /// Source exists but points to a different (or no) remote. CLI should prompt the user.
    Conflict {
        source: PathBuf,
        current_remote: Option<String>,
    },
    /// No chezmoi source exists. Proceed with `init`.
    InitRequired,
}

/// Orchestrates chezmoi source initialisation, backup, and rollback.
///
/// Holds no mutable state; construct with `ChezmoiBootstrapper::default()`.
/// CLI is responsible for prompting the user before calling destructive operations.
#[derive(Default)]
pub struct ChezmoiBootstrapper;

impl ChezmoiBootstrapper {
    /// Inspect the current chezmoi source against `url` and return the action required.
    pub fn check(&self, url: &str) -> Result<BootstrapStatus, KaizenError> {
        let existing = chezmoi::standalone_source_dir()?;
        match existing {
            None => Ok(BootstrapStatus::InitRequired),
            Some(source) => {
                let remote = chezmoi::current_remote(&source)?;
                if remote
                    .as_deref()
                    .map(|r| chezmoi::remotes_match(r, url))
                    .unwrap_or(false)
                {
                    Ok(BootstrapStatus::AlreadyUpToDate(source))
                } else {
                    Ok(BootstrapStatus::Conflict {
                        source,
                        current_remote: remote,
                    })
                }
            }
        }
    }

    /// Backup `existing` source, run `chezmoi init`, validate manifest.
    /// Returns `(new_source_dir, backup_dir)`. Rolls back on failure.
    pub fn backup_and_reinit(
        &self,
        url: &str,
        existing: &Path,
    ) -> Result<(PathBuf, PathBuf), KaizenError> {
        let backup = chezmoi::backup_source_dir(existing)?;
        if let Err(e) = self.init_and_validate(url) {
            let _ = std::fs::rename(&backup, existing);
            return Err(e);
        }
        let new_source =
            chezmoi::standalone_source_dir()?.ok_or(KaizenError::ChezmoidataTargetUnknown)?;
        Ok((new_source, backup))
    }

    /// Run `chezmoi init` and validate the resulting source manifest.
    /// Cleans up on validation failure.
    pub fn init(&self, url: &str) -> Result<PathBuf, KaizenError> {
        self.init_and_validate(url)?;
        chezmoi::standalone_source_dir()?.ok_or(KaizenError::ChezmoidataTargetUnknown)
    }

    fn init_and_validate(&self, url: &str) -> Result<(), KaizenError> {
        chezmoi::init_source(url)?;
        let source =
            chezmoi::standalone_source_dir()?.ok_or(KaizenError::ChezmoidataTargetUnknown)?;
        let kaizen_dir = source.join(manifest::KAIZEN_DIR);
        let m = manifest::load(&kaizen_dir)?;
        manifest::validate(&m)
    }
}

/// Resolve the features directory from an already-known chezmoi `source_dir`.
///
/// Used during `setup` where source_dir comes from the bootstrap step,
/// not from a chezmoi query (unlike `resolve_features_dir` in `lib.rs`).
pub fn resolve_features_dir_from_source(explicit: Option<&Path>, source_dir: &Path) -> PathBuf {
    if let Some(dir) = explicit {
        return dir.to_owned();
    }
    let candidate = source_dir
        .join(manifest::KAIZEN_DIR)
        .join(manifest::FEATURES_SUBDIR);
    if candidate.is_dir() {
        return candidate;
    }
    PathBuf::from("features")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    #[test]
    fn resolve_explicit_dir_is_returned_unchanged() {
        let dir = TempDir::new().unwrap();
        let explicit = dir.path().to_owned();
        let result = resolve_features_dir_from_source(Some(&explicit), Path::new("/irrelevant"));
        assert_eq!(result, explicit);
    }

    #[test]
    fn resolve_kaizen_features_subdir_when_it_exists() {
        let dir = TempDir::new().unwrap();
        let features = dir
            .path()
            .join(manifest::KAIZEN_DIR)
            .join(manifest::FEATURES_SUBDIR);
        fs::create_dir_all(&features).unwrap();
        let result = resolve_features_dir_from_source(None, dir.path());
        assert_eq!(result, features);
    }

    #[test]
    fn resolve_falls_back_to_builtin_when_no_kaizen_dir() {
        let dir = TempDir::new().unwrap();
        let result = resolve_features_dir_from_source(None, dir.path());
        assert_eq!(result, PathBuf::from("features"));
    }
}
