use std::path::{Path, PathBuf};

use crate::{chezmoi, chezmoi_client::ChezmoiClient, fs::FileSystem, manifest, KaizenError};

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
    /// Chezmoi reports a source path, and the git root remote matches the requested URL,
    /// but the source subdirectory (e.g. from `.chezmoiroot`) is missing — the local
    /// clone is stale. Safe to pull: the repo belongs to us.
    StaleSource {
        /// Git repository root to pull from.
        git_root: PathBuf,
        /// The source path we expect to exist after pulling.
        expected_source: PathBuf,
    },
}

/// Orchestrates chezmoi source initialisation, backup, and rollback.
///
/// Receives a `ChezmoiClient` so core logic can be tested without spawning real processes.
/// CLI is responsible for prompting the user before calling destructive operations.
pub struct ChezmoiBootstrapper {
    client: Box<dyn ChezmoiClient>,
    fs: Box<dyn FileSystem>,
}

impl ChezmoiBootstrapper {
    pub fn new(client: Box<dyn ChezmoiClient>, fs: Box<dyn FileSystem>) -> Self {
        Self { client, fs }
    }

    /// Inspect the current chezmoi source against `url` and return the action required.
    pub fn check(&self, url: &str) -> Result<BootstrapStatus, KaizenError> {
        // Fast path: source exists and is usable.
        if let Some(source) = self.client.source_path()? {
            let remote = self.client.current_remote(&source)?;
            return if remote
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
            };
        }

        // Source path not found or doesn't exist on disk.
        // Check whether chezmoi reports a path at all (raw, may be missing on disk).
        let Some(reported) = self.client.raw_source_path()? else {
            return Ok(BootstrapStatus::InitRequired);
        };

        // Chezmoi has a configured source but the reported path doesn't exist.
        // This happens when `.chezmoiroot` points to a subdirectory added after
        // the initial clone (stale local copy).
        // Find the git root of the parent directory and check its remote.
        let parent = reported.parent().unwrap_or(&reported);
        let remote = self.client.current_remote(parent)?;

        match remote {
            Some(r) if chezmoi::remotes_match(&r, url) => Ok(BootstrapStatus::StaleSource {
                git_root: parent.to_owned(),
                expected_source: reported,
            }),
            Some(r) => Ok(BootstrapStatus::Conflict {
                source: parent.to_owned(),
                current_remote: Some(r),
            }),
            None => Ok(BootstrapStatus::InitRequired),
        }
    }

    /// Backup `existing` source (or its git root), run `chezmoi init`, validate manifest.
    /// Returns `(new_source_dir, backup_path)`. Rolls back on failure.
    pub fn backup_and_reinit(
        &self,
        url: &str,
        existing: &Path,
    ) -> Result<(PathBuf, PathBuf), KaizenError> {
        let backup = self.client.backup_source_dir(existing)?;
        let result = self.init(url);
        if let Err(e) = result {
            let _ = self.fs.rename(&backup.backup_path, &backup.restore_path);
            return Err(e);
        }
        let new_source = self
            .client
            .source_path()?
            .ok_or(KaizenError::ChezmoidataTargetUnknown)?;
        Ok((new_source, backup.backup_path))
    }

    /// Run `chezmoi init` and validate the resulting source has `kaizen/features`.
    pub fn init(&self, url: &str) -> Result<PathBuf, KaizenError> {
        self.client.init_source(url)?;
        let source = self
            .client
            .source_path()?
            .ok_or(KaizenError::ChezmoidataTargetUnknown)?;
        let features_dir = source
            .join(manifest::KAIZEN_DIR)
            .join(manifest::FEATURES_SUBDIR);
        if !self.fs.is_dir(&features_dir) {
            return Err(KaizenError::FeaturesDirNotFound { path: features_dir });
        }
        Ok(source)
    }
}

/// Resolve the features directory from an already-known chezmoi `source_dir`.
///
/// Returns the expected `kaizen/features` path under `source_dir` regardless
/// of whether it already exists. Callers receive a clear `FeaturesDirNotFound`
/// error from `FeatureStore` when the directory is absent.
pub fn resolve_features_dir_from_source(
    explicit: Option<&Path>,
    source_dir: &Path,
    _fs: &dyn FileSystem,
) -> PathBuf {
    if let Some(dir) = explicit {
        return dir.to_owned();
    }
    source_dir
        .join(manifest::KAIZEN_DIR)
        .join(manifest::FEATURES_SUBDIR)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{chezmoi_client::SourceBackup, fs::mem::MemFileSystem, RemoveFilesReport};

    // TestChezmoiClient kept for potential future tests
    #[allow(dead_code)]
    struct TestChezmoiClient {
        source: PathBuf,
        backup: PathBuf,
    }

    impl ChezmoiClient for TestChezmoiClient {
        fn managed_files(&self) -> Result<Vec<PathBuf>, KaizenError> {
            Ok(vec![])
        }

        fn locally_modified_files(&self) -> Result<Vec<PathBuf>, KaizenError> {
            Ok(vec![])
        }

        fn source_path(&self) -> Result<Option<PathBuf>, KaizenError> {
            Ok(Some(self.source.clone()))
        }
        fn raw_source_path(&self) -> Result<Option<PathBuf>, KaizenError> {
            Ok(Some(self.source.clone()))
        }
        fn pull_source(&self, _: &Path) -> Result<(), KaizenError> {
            Ok(())
        }
        fn current_remote(&self, _: &Path) -> Result<Option<String>, KaizenError> {
            Ok(None)
        }

        fn init_source(&self, _: &str) -> Result<(), KaizenError> {
            Ok(())
        }

        fn apply(&self, _force: bool) -> Result<(), KaizenError> {
            Ok(())
        }

        fn remove_files(
            &self,
            files: &[PathBuf],
            _: bool,
        ) -> Result<RemoveFilesReport, KaizenError> {
            Ok(RemoveFilesReport {
                removed: files.to_vec(),
                skipped: vec![],
            })
        }

        fn backup_source_dir(&self, source_dir: &Path) -> Result<SourceBackup, KaizenError> {
            Ok(SourceBackup {
                backup_path: self.backup.clone(),
                restore_path: source_dir.to_owned(),
            })
        }
    }

    #[test]
    fn resolve_explicit_dir_is_returned_unchanged() {
        let fs = MemFileSystem::new();
        let explicit = PathBuf::from("/explicit");
        let result =
            resolve_features_dir_from_source(Some(&explicit), Path::new("/irrelevant"), &fs);
        assert_eq!(result, explicit);
    }

    #[test]
    fn resolve_kaizen_features_subdir_when_it_exists() {
        let fs = MemFileSystem::new();
        let source = PathBuf::from("/source");
        let features = source
            .join(manifest::KAIZEN_DIR)
            .join(manifest::FEATURES_SUBDIR);
        fs.add_dir(&features);
        let result = resolve_features_dir_from_source(None, &source, &fs);
        assert_eq!(result, features);
    }

    #[test]
    fn resolve_returns_expected_path_even_when_dir_absent() {
        let fs = MemFileSystem::new();
        let result = resolve_features_dir_from_source(None, Path::new("/source"), &fs);
        assert_eq!(
            result,
            PathBuf::from("/source")
                .join(manifest::KAIZEN_DIR)
                .join(manifest::FEATURES_SUBDIR)
        );
    }

    #[test]
    fn init_errors_when_source_has_no_kaizen_features() {
        use crate::{chezmoi_client::SourceBackup, RemoveFilesReport};
        struct FakeClient {
            source: PathBuf,
        }
        impl ChezmoiClient for FakeClient {
            fn managed_files(&self) -> Result<Vec<PathBuf>, KaizenError> {
                Ok(vec![])
            }
            fn locally_modified_files(&self) -> Result<Vec<PathBuf>, KaizenError> {
                Ok(vec![])
            }
            fn source_path(&self) -> Result<Option<PathBuf>, KaizenError> {
                Ok(Some(self.source.clone()))
            }
            fn raw_source_path(&self) -> Result<Option<PathBuf>, KaizenError> {
                Ok(Some(self.source.clone()))
            }
            fn pull_source(&self, _: &Path) -> Result<(), KaizenError> {
                Ok(())
            }
            fn current_remote(&self, _: &Path) -> Result<Option<String>, KaizenError> {
                Ok(None)
            }
            fn init_source(&self, _: &str) -> Result<(), KaizenError> {
                Ok(())
            }
            fn apply(&self, _: bool) -> Result<(), KaizenError> {
                Ok(())
            }
            fn remove_files(
                &self,
                f: &[PathBuf],
                _: bool,
            ) -> Result<RemoveFilesReport, KaizenError> {
                Ok(RemoveFilesReport {
                    removed: f.to_vec(),
                    skipped: vec![],
                })
            }
            fn backup_source_dir(&self, p: &Path) -> Result<SourceBackup, KaizenError> {
                Ok(SourceBackup {
                    backup_path: p.with_extension("bak"),
                    restore_path: p.to_owned(),
                })
            }
        }
        let fs = MemFileSystem::new();
        let bootstrapper = ChezmoiBootstrapper::new(
            Box::new(FakeClient {
                source: PathBuf::from("/source"),
            }),
            Box::new(fs),
        );
        assert!(matches!(
            bootstrapper.init("https://example.com/dotfiles"),
            Err(KaizenError::FeaturesDirNotFound { .. })
        ));
    }
}
