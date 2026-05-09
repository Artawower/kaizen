use std::path::{Path, PathBuf};

use crate::{chezmoi, chezmoi_client::ChezmoiClient, manifest, KaizenError};

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
/// Receives a `ChezmoiClient` so core logic can be tested without spawning real processes.
/// CLI is responsible for prompting the user before calling destructive operations.
pub struct ChezmoiBootstrapper {
    client: Box<dyn ChezmoiClient>,
}

impl ChezmoiBootstrapper {
    pub fn new(client: Box<dyn ChezmoiClient>) -> Self {
        Self { client }
    }

    /// Inspect the current chezmoi source against `url` and return the action required.
    pub fn check(&self, url: &str) -> Result<BootstrapStatus, KaizenError> {
        match self.client.source_path()? {
            None => Ok(BootstrapStatus::InitRequired),
            Some(source) => {
                let remote = self.client.current_remote(&source)?;
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
        let backup = self.client.backup_source_dir(existing)?;
        if let Err(e) = self.init_and_validate(url) {
            let _ = std::fs::rename(&backup, existing);
            return Err(e);
        }
        let new_source = self
            .client
            .source_path()?
            .ok_or(KaizenError::ChezmoidataTargetUnknown)?;
        Ok((new_source, backup))
    }

    /// Run `chezmoi init` and validate the resulting source manifest.
    pub fn init(&self, url: &str) -> Result<PathBuf, KaizenError> {
        self.init_and_validate(url)?;
        self.client
            .source_path()?
            .ok_or(KaizenError::ChezmoidataTargetUnknown)
    }

    fn init_and_validate(&self, url: &str) -> Result<(), KaizenError> {
        self.client.init_source(url)?;
        let source = self
            .client
            .source_path()?
            .ok_or(KaizenError::ChezmoidataTargetUnknown)?;
        let kaizen_dir = source.join(manifest::KAIZEN_DIR);
        let m = manifest::load(&kaizen_dir)?;
        manifest::validate(&m)
    }
}

/// Resolve the features directory from an already-known chezmoi `source_dir`.
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
