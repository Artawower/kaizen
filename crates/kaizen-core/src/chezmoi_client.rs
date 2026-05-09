use std::path::{Path, PathBuf};

use crate::{chezmoi::RemoveFilesReport, KaizenError};

/// Backup result: what was backed up and where to restore it on rollback.
///
/// `backup_path` and `restore_path` may differ when the effective chezmoi
/// source is a subdirectory of a git repo (e.g. with `.chezmoiroot`).
/// In that case the git root is backed up, so rollback must restore to the
/// git root, not to the subdirectory path.
pub struct SourceBackup {
    /// Path the original directory was moved to.
    pub backup_path: PathBuf,
    /// Path to restore the backup to on rollback (the original git root).
    pub restore_path: PathBuf,
}

/// Port for all external chezmoi interactions (process calls + related FS ops).
///
/// Concrete implementation (`StdChezmoiClient`) lives in kaizen-cli.
/// Core backends receive this via `Runtime` injection.
pub trait ChezmoiClient: Send + Sync {
    /// Run `chezmoi managed --include=files --path-style=absolute`.
    fn managed_files(&self) -> Result<Vec<PathBuf>, KaizenError>;

    /// Run `chezmoi status` and return locally-modified tracked files.
    fn locally_modified_files(&self) -> Result<Vec<PathBuf>, KaizenError>;

    /// Run `chezmoi source-path` and return the current source directory, or `None`.
    fn source_path(&self) -> Result<Option<PathBuf>, KaizenError>;

    /// Run `git remote get-url origin` inside `source_dir`.
    fn current_remote(&self, source_dir: &Path) -> Result<Option<String>, KaizenError>;

    /// Run `chezmoi init <url>`.
    fn init_source(&self, url: &str) -> Result<(), KaizenError>;

    /// Run `chezmoi apply` (with stderr captured for error messages).
    fn apply(&self) -> Result<(), KaizenError>;

    /// Remove dotfiles from disk. Dry-run collects the plan without deleting.
    fn remove_files(
        &self,
        files: &[PathBuf],
        dry_run: bool,
    ) -> Result<RemoveFilesReport, KaizenError>;

    /// Back up the source directory (or its git root) to a timestamped path.
    ///
    /// When `source_dir` is a subdirectory of a git repo (`.chezmoiroot` case),
    /// the entire git root is backed up so that rollback can fully restore state.
    /// Falls back to backing up `source_dir` itself for non-git sources.
    fn backup_source_dir(&self, source_dir: &Path) -> Result<SourceBackup, KaizenError>;
}

/// No-op client: succeeds without touching the filesystem or spawning processes.
/// Used in tests that exercise backend logic without a real chezmoi installation.
pub struct NoopChezmoiClient;

impl ChezmoiClient for NoopChezmoiClient {
    fn managed_files(&self) -> Result<Vec<PathBuf>, KaizenError> {
        Ok(vec![])
    }
    fn locally_modified_files(&self) -> Result<Vec<PathBuf>, KaizenError> {
        Ok(vec![])
    }
    fn source_path(&self) -> Result<Option<PathBuf>, KaizenError> {
        Ok(None)
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
    fn remove_files(&self, files: &[PathBuf], _: bool) -> Result<RemoveFilesReport, KaizenError> {
        Ok(RemoveFilesReport {
            removed: files.to_vec(),
            skipped: vec![],
        })
    }
    fn backup_source_dir(&self, source_dir: &Path) -> Result<SourceBackup, KaizenError> {
        let backup_path = source_dir.with_extension("bak");
        Ok(SourceBackup {
            backup_path,
            restore_path: source_dir.to_owned(),
        })
    }
}
