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

    /// Backup `existing` source (or its git root), run `chezmoi init`, validate manifest.
    /// Returns `(new_source_dir, backup_path)`. Rolls back on failure.
    pub fn backup_and_reinit(
        &self,
        url: &str,
        existing: &Path,
    ) -> Result<(PathBuf, PathBuf), KaizenError> {
        let backup = self.client.backup_source_dir(existing)?;
        if let Err(e) = self.init_and_validate(url) {
            let _ = self.fs.rename(&backup.backup_path, &backup.restore_path);
            return Err(e);
        }
        let new_source = self
            .client
            .source_path()?
            .ok_or(KaizenError::ChezmoidataTargetUnknown)?;
        Ok((new_source, backup.backup_path))
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
        let m = manifest::load_with(&kaizen_dir, self.fs.as_ref())?;
        manifest::validate(&m)
    }
}

/// Resolve the features directory from an already-known chezmoi `source_dir`.
pub fn resolve_features_dir_from_source(
    explicit: Option<&Path>,
    source_dir: &Path,
    fs: &dyn FileSystem,
) -> PathBuf {
    if let Some(dir) = explicit {
        return dir.to_owned();
    }
    let candidate = source_dir
        .join(manifest::KAIZEN_DIR)
        .join(manifest::FEATURES_SUBDIR);
    if fs.is_dir(&candidate) {
        return candidate;
    }
    PathBuf::from("features")
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use super::*;
    use crate::{chezmoi_client::SourceBackup, fs::mem::MemFileSystem, RemoveFilesReport};

    struct TestChezmoiClient {
        source: PathBuf,
        backup: PathBuf,
    }

    impl TestChezmoiClient {
        fn new(source: impl Into<PathBuf>, backup: impl Into<PathBuf>) -> Self {
            Self {
                source: source.into(),
                backup: backup.into(),
            }
        }
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

        fn current_remote(&self, _: &Path) -> Result<Option<String>, KaizenError> {
            Ok(None)
        }

        fn init_source(&self, _: &str) -> Result<(), KaizenError> {
            Ok(())
        }

        fn apply(&self) -> Result<(), KaizenError> {
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

    struct RecordingFileSystem {
        inner: MemFileSystem,
        renames: Arc<Mutex<Vec<(PathBuf, PathBuf)>>>,
    }

    impl RecordingFileSystem {
        fn new() -> Self {
            Self {
                inner: MemFileSystem::new(),
                renames: Arc::new(Mutex::new(vec![])),
            }
        }

        fn add_file(&self, path: impl Into<PathBuf>, content: impl Into<Vec<u8>>) {
            self.inner.add_file(path, content);
        }
    }

    impl FileSystem for RecordingFileSystem {
        fn read_to_string(&self, path: &Path) -> Result<String, KaizenError> {
            self.inner.read_to_string(path)
        }

        fn read_dir_paths(&self, path: &Path) -> Result<Vec<PathBuf>, KaizenError> {
            self.inner.read_dir_paths(path)
        }

        fn exists(&self, path: &Path) -> bool {
            self.inner.exists(path)
        }

        fn is_dir(&self, path: &Path) -> bool {
            self.inner.is_dir(path)
        }

        fn write(&self, path: &Path, content: &[u8]) -> Result<(), KaizenError> {
            self.inner.write(path, content)
        }

        fn create_dir_all(&self, path: &Path) -> Result<(), KaizenError> {
            self.inner.create_dir_all(path)
        }

        fn rename(&self, from: &Path, to: &Path) -> Result<(), KaizenError> {
            self.renames
                .lock()
                .unwrap()
                .push((from.to_owned(), to.to_owned()));
            Ok(())
        }

        fn remove_file(&self, path: &Path) -> Result<(), KaizenError> {
            self.inner.remove_file(path)
        }

        fn remove_dir_all(&self, path: &Path) -> Result<(), KaizenError> {
            self.inner.remove_dir_all(path)
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
    fn resolve_falls_back_to_builtin_when_no_kaizen_dir() {
        let fs = MemFileSystem::new();
        let result = resolve_features_dir_from_source(None, Path::new("/source"), &fs);
        assert_eq!(result, PathBuf::from("features"));
    }

    #[test]
    fn init_validates_manifest_through_injected_filesystem() {
        let fs = MemFileSystem::new();
        let source = PathBuf::from("/source");
        fs.add_file(
            source.join(manifest::KAIZEN_DIR).join("manifest.toml"),
            "schema_version = 999",
        );
        let bootstrapper = ChezmoiBootstrapper::new(
            Box::new(TestChezmoiClient::new(&source, "/backup")),
            Box::new(fs),
        );

        let error = bootstrapper
            .init("https://example.com/dotfiles")
            .unwrap_err();

        assert!(matches!(error, KaizenError::ManifestSchemaTooNew { .. }));
    }

    #[test]
    fn backup_and_reinit_rolls_back_when_manifest_validation_fails() {
        let fs = RecordingFileSystem::new();
        let existing = PathBuf::from("/existing");
        let source = PathBuf::from("/source");
        let backup = PathBuf::from("/backup");
        fs.add_file(
            source.join(manifest::KAIZEN_DIR).join("manifest.toml"),
            "schema_version = 999",
        );
        let renames = Arc::clone(&fs.renames);
        let bootstrapper = ChezmoiBootstrapper::new(
            Box::new(TestChezmoiClient::new(&source, &backup)),
            Box::new(fs),
        );

        let error = bootstrapper
            .backup_and_reinit("https://example.com/dotfiles", &existing)
            .unwrap_err();

        assert!(matches!(error, KaizenError::ManifestSchemaTooNew { .. }));
        assert_eq!(renames.lock().unwrap().as_slice(), &[(backup, existing)]);
    }
}
