use std::path::{Path, PathBuf};

use kaizen_core::{FileSystem, KaizenError};

pub struct StdFileSystem;

impl FileSystem for StdFileSystem {
    fn read_to_string(&self, path: &Path) -> Result<String, KaizenError> {
        std::fs::read_to_string(path).map_err(KaizenError::Io)
    }

    fn read_dir_paths(&self, path: &Path) -> Result<Vec<PathBuf>, KaizenError> {
        let entries = std::fs::read_dir(path).map_err(KaizenError::Io)?;
        let mut paths = Vec::new();
        for entry in entries {
            paths.push(entry.map_err(KaizenError::Io)?.path());
        }
        Ok(paths)
    }

    fn exists(&self, path: &Path) -> bool {
        path.exists()
    }

    fn is_dir(&self, path: &Path) -> bool {
        path.is_dir()
    }

    fn write(&self, path: &Path, content: &[u8]) -> Result<(), KaizenError> {
        std::fs::write(path, content).map_err(KaizenError::Io)
    }

    fn create_dir_all(&self, path: &Path) -> Result<(), KaizenError> {
        std::fs::create_dir_all(path).map_err(KaizenError::Io)
    }

    fn rename(&self, from: &Path, to: &Path) -> Result<(), KaizenError> {
        std::fs::rename(from, to).map_err(KaizenError::Io)
    }

    fn remove_file(&self, path: &Path) -> Result<(), KaizenError> {
        std::fs::remove_file(path).map_err(KaizenError::Io)
    }

    fn remove_dir_all(&self, path: &Path) -> Result<(), KaizenError> {
        std::fs::remove_dir_all(path).map_err(KaizenError::Io)
    }
}
