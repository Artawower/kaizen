use std::path::{Path, PathBuf};

use crate::{chezmoi::RemoveFilesReport, KaizenError};

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

    /// Remove dotfiles from disk.  Dry-run collects the plan without deleting.
    fn remove_files(
        &self,
        files: &[PathBuf],
        dry_run: bool,
    ) -> Result<RemoveFilesReport, KaizenError>;

    /// Move `source_dir` to a timestamped backup path and return the backup path.
    fn backup_source_dir(&self, source_dir: &Path) -> Result<PathBuf, KaizenError>;
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
    fn backup_source_dir(&self, source_dir: &Path) -> Result<PathBuf, KaizenError> {
        Ok(source_dir.with_extension("bak"))
    }
}
