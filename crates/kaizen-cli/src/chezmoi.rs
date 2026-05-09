use std::{
    io::Read,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

use kaizen_core::{
    chezmoi::{
        parse_managed_files, parse_source_path_output, parse_status_output, FileStatus,
        RemoveFilesReport,
    },
    chezmoi_client::{ChezmoiClient, SourceBackup},
    KaizenError,
};

/// Return the git repository root containing `dir`, or `None` if not in a git repo.
/// Falls back gracefully so non-git dotfiles sources still work.
fn git_root(dir: &Path) -> Option<PathBuf> {
    let out = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let path = std::str::from_utf8(&out.stdout).ok()?.trim();
    Some(PathBuf::from(path))
}

/// Concrete chezmoi client that spawns real processes.
///
/// Lives in CLI, not core, because it uses `std::process::Command`.
pub struct StdChezmoiClient;

impl ChezmoiClient for StdChezmoiClient {
    fn managed_files(&self) -> Result<Vec<PathBuf>, KaizenError> {
        let home = dirs::home_dir().ok_or(KaizenError::HomeDirUnavailable)?;
        let out = Command::new("chezmoi")
            .args(["managed", "--include=files", "--path-style=absolute"])
            .output()?;
        if !out.status.success() {
            return Ok(vec![]);
        }
        Ok(parse_managed_files(
            &String::from_utf8_lossy(&out.stdout),
            &home,
        ))
    }

    fn locally_modified_files(&self) -> Result<Vec<PathBuf>, KaizenError> {
        let home = dirs::home_dir().ok_or(KaizenError::HomeDirUnavailable)?;
        let out = Command::new("chezmoi").arg("status").output()?;
        if !out.status.success() {
            return Ok(vec![]);
        }
        Ok(
            parse_status_output(&String::from_utf8_lossy(&out.stdout), &home)
                .into_iter()
                .filter(|f| f.status == FileStatus::Modified)
                .map(|f| f.path)
                .collect(),
        )
    }

    fn source_path(&self) -> Result<Option<PathBuf>, KaizenError> {
        let out = Command::new("chezmoi").arg("source-path").output()?;
        if !out.status.success() {
            return Ok(None);
        }
        let raw = String::from_utf8_lossy(&out.stdout);
        match parse_source_path_output(&raw) {
            Some(path) if path.exists() => Ok(Some(path)),
            _ => Ok(None),
        }
    }

    fn current_remote(&self, source_dir: &Path) -> Result<Option<String>, KaizenError> {
        let out = Command::new("git")
            .arg("-C")
            .arg(source_dir)
            .args(["remote", "get-url", "origin"])
            .output()?;
        if !out.status.success() {
            return Ok(None);
        }
        Ok(Some(String::from_utf8_lossy(&out.stdout).trim().to_owned()))
    }

    fn init_source(&self, url: &str) -> Result<(), KaizenError> {
        let status = Command::new("chezmoi").args(["init", url]).status()?;
        if !status.success() {
            return Err(KaizenError::ChezmoidataInitFailed {
                url: url.to_owned(),
                code: status.code(),
            });
        }
        Ok(())
    }

    fn apply(&self) -> Result<(), KaizenError> {
        let mut child = Command::new("chezmoi")
            .arg("apply")
            .stderr(Stdio::piped())
            .spawn()?;
        let stderr_bytes = child
            .stderr
            .take()
            .map(|mut s| {
                let mut buf = Vec::new();
                let _ = s.read_to_end(&mut buf);
                buf
            })
            .unwrap_or_default();
        let status = child.wait()?;
        if !status.success() {
            let stderr = String::from_utf8_lossy(&stderr_bytes).trim().to_owned();
            return Err(KaizenError::ChezmoidataApplyFailed {
                code: status.code(),
                reason: if stderr.is_empty() {
                    None
                } else {
                    Some(stderr)
                },
            });
        }
        Ok(())
    }

    fn remove_files(
        &self,
        files: &[PathBuf],
        dry_run: bool,
    ) -> Result<RemoveFilesReport, KaizenError> {
        let mut report = RemoveFilesReport::default();
        for file in files {
            if !file.exists() {
                report.skipped.push(file.clone());
                continue;
            }
            if !dry_run {
                std::fs::remove_file(file).map_err(KaizenError::Io)?;
            }
            report.removed.push(file.clone());
        }
        Ok(report)
    }

    fn backup_source_dir(&self, source_dir: &Path) -> Result<SourceBackup, KaizenError> {
        let restore_path = git_root(source_dir).unwrap_or_else(|| source_dir.to_owned());
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let name = restore_path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy();
        let backup_path = restore_path.with_file_name(format!("{name}.bak.{ts}"));
        std::fs::rename(&restore_path, &backup_path)?;
        Ok(SourceBackup {
            backup_path,
            restore_path,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// backup_source_dir must back up the git root, not the source subdirectory,
    /// when the chezmoi source is nested inside a git repo (.chezmoiroot case).
    #[test]
    fn backup_targets_git_root_when_source_is_subdir() {
        let repo = tempfile::tempdir().unwrap();
        let repo_path = repo.path();

        // Initialise a real git repo
        std::process::Command::new("git")
            .args(["init", "-q"])
            .current_dir(repo_path)
            .status()
            .unwrap();

        // Simulate .chezmoiroot = dotfiles
        let source_dir = repo_path.join("dotfiles");
        std::fs::create_dir_all(&source_dir).unwrap();

        // Canonicalize before backup: after rename the original path no longer exists.
        // On macOS /tmp is a symlink to /private/tmp; git returns the resolved path.
        let canonical_root = repo_path.canonicalize().unwrap();
        let canonical_parent = canonical_root.parent().unwrap().to_owned();

        let client = StdChezmoiClient;
        let backup = client.backup_source_dir(&source_dir).unwrap();

        // restore_path must be the git root, not dotfiles/
        assert_eq!(backup.restore_path, canonical_root);
        // backup_path must be a sibling of the repo root, not of dotfiles/
        assert_eq!(backup.backup_path.parent().unwrap(), canonical_parent);
    }

    /// When source_dir is not inside a git repo, fallback to backing up source_dir itself.
    #[test]
    fn backup_falls_back_to_source_dir_when_not_git() {
        let dir = tempfile::tempdir().unwrap();
        let source_dir = dir.path().to_owned();

        let client = StdChezmoiClient;
        let backup = client.backup_source_dir(&source_dir).unwrap();

        assert_eq!(backup.restore_path, source_dir);
    }
}
