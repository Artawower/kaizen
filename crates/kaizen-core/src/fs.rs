use std::path::{Path, PathBuf};

use crate::KaizenError;

/// Port for filesystem access.
///
/// Concrete implementations: `StdFileSystem` (production), `MemFileSystem` (tests).
/// Loaders expose `_with(path, fs)` variants so callers can inject in tests.
pub trait FileSystem: Send + Sync {
    fn read_to_string(&self, path: &Path) -> Result<String, KaizenError>;
    fn read_dir_paths(&self, path: &Path) -> Result<Vec<PathBuf>, KaizenError>;
    fn exists(&self, path: &Path) -> bool;
    fn is_dir(&self, path: &Path) -> bool;
    fn write(&self, path: &Path, content: &[u8]) -> Result<(), KaizenError>;
    fn create_dir_all(&self, path: &Path) -> Result<(), KaizenError>;
    fn rename(&self, from: &Path, to: &Path) -> Result<(), KaizenError>;
    fn remove_file(&self, path: &Path) -> Result<(), KaizenError>;
    fn remove_dir_all(&self, path: &Path) -> Result<(), KaizenError>;
}

/// Standard filesystem implementation backed by `std::fs`.
pub struct StdFileSystem;

impl FileSystem for StdFileSystem {
    fn read_to_string(&self, path: &Path) -> Result<String, KaizenError> {
        std::fs::read_to_string(path).map_err(KaizenError::Io)
    }

    fn read_dir_paths(&self, path: &Path) -> Result<Vec<PathBuf>, KaizenError> {
        let entries = std::fs::read_dir(path).map_err(KaizenError::Io)?;
        entries
            .map(|e| e.map(|e| e.path()).map_err(KaizenError::Io))
            .collect()
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

#[cfg(test)]
pub mod mem {
    use std::{
        collections::HashMap,
        path::{Path, PathBuf},
        sync::Mutex,
    };

    use super::*;

    /// In-memory filesystem for unit tests. No disk I/O.
    pub struct MemFileSystem {
        files: Mutex<HashMap<PathBuf, Vec<u8>>>,
    }

    impl MemFileSystem {
        pub fn new() -> Self {
            Self {
                files: Mutex::new(HashMap::new()),
            }
        }

        pub fn add_file(&self, path: impl Into<PathBuf>, content: impl Into<Vec<u8>>) {
            self.files.lock().unwrap().insert(path.into(), content.into());
        }
    }

    impl FileSystem for MemFileSystem {
        fn read_to_string(&self, path: &Path) -> Result<String, KaizenError> {
            let files = self.files.lock().unwrap();
            files
                .get(path)
                .map(|b| String::from_utf8_lossy(b).into_owned())
                .ok_or_else(|| KaizenError::Io(std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    path.display().to_string(),
                )))
        }

        fn read_dir_paths(&self, path: &Path) -> Result<Vec<PathBuf>, KaizenError> {
            let files = self.files.lock().unwrap();
            let mut paths: Vec<PathBuf> = files
                .keys()
                .filter(|p| p.parent() == Some(path))
                .cloned()
                .collect();
            paths.sort();
            Ok(paths)
        }

        fn exists(&self, path: &Path) -> bool {
            self.files.lock().unwrap().contains_key(path)
        }

        fn is_dir(&self, path: &Path) -> bool {
            let files = self.files.lock().unwrap();
            files.keys().any(|p| p.parent() == Some(path))
        }

        fn write(&self, path: &Path, content: &[u8]) -> Result<(), KaizenError> {
            self.files.lock().unwrap().insert(path.to_owned(), content.to_vec());
            Ok(())
        }

        fn create_dir_all(&self, _path: &Path) -> Result<(), KaizenError> {
            Ok(())
        }

        fn rename(&self, from: &Path, to: &Path) -> Result<(), KaizenError> {
            let mut files = self.files.lock().unwrap();
            let content = files.remove(from).ok_or_else(|| KaizenError::Io(
                std::io::Error::new(std::io::ErrorKind::NotFound, from.display().to_string()),
            ))?;
            files.insert(to.to_owned(), content);
            Ok(())
        }

        fn remove_file(&self, path: &Path) -> Result<(), KaizenError> {
            let removed = self.files.lock().unwrap().remove(path);
            removed.map(|_| ()).ok_or_else(|| KaizenError::Io(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                path.display().to_string(),
            )))
        }

        fn remove_dir_all(&self, path: &Path) -> Result<(), KaizenError> {
            let mut files = self.files.lock().unwrap();
            let to_remove: Vec<_> = files.keys().filter(|p| p.starts_with(path)).cloned().collect();
            for p in to_remove { files.remove(&p); }
            Ok(())
        }
    }
}
