use std::path::{Path, PathBuf};

use crate::{chezmoi::RemoveFilesReport, KaizenError};

/// Backup result: what was backed up and where to restore it on rollback.
pub struct SourceBackup {
    pub backup_path: PathBuf,
    pub restore_path: PathBuf,
}

/// Port for all external chezmoi interactions (process calls + related FS ops).
pub trait ChezmoiClient: Send + Sync {
    fn managed_files(&self) -> Result<Vec<PathBuf>, KaizenError>;
    fn locally_modified_files(&self) -> Result<Vec<PathBuf>, KaizenError>;

    /// Run `chezmoi source-path` and return the path **only when it exists** on disk.
    fn source_path(&self) -> Result<Option<PathBuf>, KaizenError>;

    /// Run `chezmoi source-path` and return whatever chezmoi reports, even if the
    /// path does not exist yet (e.g. `.chezmoiroot` subdir missing in stale clone).
    fn raw_source_path(&self) -> Result<Option<PathBuf>, KaizenError>;

    /// Return the physical repository root for destructive operations (uninstall, backup).
    ///
    /// Unlike `source_path()` this does **not** require the path to exist on disk,
    /// so it works even when the `.chezmoiroot` subdirectory is missing (stale clone).
    /// When the raw path exists, `resolve_source_root` is called with it directly;
    /// when it does not exist, the *parent* is used so the git root can be found.
    fn source_root(&self) -> Result<Option<PathBuf>, KaizenError> {
        let Some(p) = self.raw_source_path()? else {
            return Ok(None);
        };
        let search_from = if p.exists() {
            p.clone()
        } else {
            p.parent().unwrap_or(&p).to_owned()
        };
        Ok(Some(self.resolve_source_root(&search_from)))
    }

    /// Resolve the physical root from an effective source path.
    ///
    /// Default implementation returns the path unchanged.
    /// `StdChezmoiClient` overrides this with `git_root()` detection.
    fn resolve_source_root(&self, effective: &Path) -> PathBuf {
        effective.to_owned()
    }

    fn pull_source(&self, git_root: &Path) -> Result<(), KaizenError>;
    fn current_remote(&self, source_dir: &Path) -> Result<Option<String>, KaizenError>;
    fn init_source(&self, url: &str) -> Result<(), KaizenError>;
    fn apply(&self, force: bool) -> Result<(), KaizenError>;
    fn remove_files(&self, files: &[PathBuf], dry_run: bool) -> Result<RemoveFilesReport, KaizenError>;
    fn backup_source_dir(&self, source_dir: &Path) -> Result<SourceBackup, KaizenError>;
}

/// No-op client for tests that exercise backend logic without a real chezmoi installation.
pub struct NoopChezmoiClient;

impl ChezmoiClient for NoopChezmoiClient {
    fn managed_files(&self) -> Result<Vec<PathBuf>, KaizenError> { Ok(vec![]) }
    fn locally_modified_files(&self) -> Result<Vec<PathBuf>, KaizenError> { Ok(vec![]) }
    fn source_path(&self) -> Result<Option<PathBuf>, KaizenError> { Ok(None) }
    fn raw_source_path(&self) -> Result<Option<PathBuf>, KaizenError> { Ok(None) }
    fn pull_source(&self, _: &Path) -> Result<(), KaizenError> { Ok(()) }
    fn current_remote(&self, _: &Path) -> Result<Option<String>, KaizenError> { Ok(None) }
    fn init_source(&self, _: &str) -> Result<(), KaizenError> { Ok(()) }
    fn apply(&self, _: bool) -> Result<(), KaizenError> { Ok(()) }
    fn remove_files(&self, files: &[PathBuf], _: bool) -> Result<RemoveFilesReport, KaizenError> {
        Ok(RemoveFilesReport { removed: files.to_vec(), skipped: vec![] })
    }
    fn backup_source_dir(&self, source_dir: &Path) -> Result<SourceBackup, KaizenError> {
        Ok(SourceBackup {
            backup_path: source_dir.with_extension("bak"),
            restore_path: source_dir.to_owned(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    /// Stub with a controllable `raw_source_path`.
    /// `resolve_source_root` appends ".resolved" so tests can assert
    /// *which path* was passed into it.
    struct StubClient {
        raw: Option<PathBuf>,
    }

    impl ChezmoiClient for StubClient {
        fn managed_files(&self) -> Result<Vec<PathBuf>, KaizenError> { Ok(vec![]) }
        fn locally_modified_files(&self) -> Result<Vec<PathBuf>, KaizenError> { Ok(vec![]) }
        fn source_path(&self) -> Result<Option<PathBuf>, KaizenError> {
            Ok(self.raw.as_ref().filter(|p| p.exists()).cloned())
        }
        fn raw_source_path(&self) -> Result<Option<PathBuf>, KaizenError> {
            Ok(self.raw.clone())
        }
        fn resolve_source_root(&self, effective: &Path) -> PathBuf {
            effective.with_extension("resolved")
        }
        fn pull_source(&self, _: &Path) -> Result<(), KaizenError> { Ok(()) }
        fn current_remote(&self, _: &Path) -> Result<Option<String>, KaizenError> { Ok(None) }
        fn init_source(&self, _: &str) -> Result<(), KaizenError> { Ok(()) }
        fn apply(&self, _: bool) -> Result<(), KaizenError> { Ok(()) }
        fn remove_files(&self, files: &[PathBuf], _: bool) -> Result<RemoveFilesReport, KaizenError> {
            Ok(RemoveFilesReport { removed: files.to_vec(), skipped: vec![] })
        }
        fn backup_source_dir(&self, src: &Path) -> Result<SourceBackup, KaizenError> {
            Ok(SourceBackup { backup_path: src.with_extension("bak"), restore_path: src.to_owned() })
        }
    }

    #[test]
    fn source_root_none_when_not_configured() {
        let c = StubClient { raw: None };
        assert_eq!(c.source_root().unwrap(), None);
    }

    #[test]
    fn source_root_resolves_from_path_when_it_exists() {
        // Create a real directory so p.exists() returns true.
        let dir = tempfile::tempdir().unwrap();
        let dotfiles = dir.path().join("dotfiles");
        std::fs::create_dir_all(&dotfiles).unwrap();

        let c = StubClient { raw: Some(dotfiles.clone()) };
        let root = c.source_root().unwrap().unwrap();
        assert_eq!(root, dotfiles.with_extension("resolved"));
    }

    #[test]
    fn source_root_resolves_from_parent_when_subdir_missing() {
        // Stale clone: chezmoi reports .../dotfiles but the dir does NOT exist.
        // source_root() must fall back to the parent so git-root detection works.
        let dir = tempfile::tempdir().unwrap();
        let dotfiles = dir.path().join("dotfiles"); // not created on disk

        let c = StubClient { raw: Some(dotfiles) };
        let root = c.source_root().unwrap().unwrap();
        // parent is dir.path()  →  dir.path().with_extension("resolved")
        assert_eq!(root, dir.path().with_extension("resolved"));
    }
}
