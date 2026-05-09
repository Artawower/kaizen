use std::path::{Path, PathBuf};

use crate::KaizenError;

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

#[cfg(test)]
pub mod mem {
    use std::{
        collections::{HashMap, HashSet},
        path::{Path, PathBuf},
        sync::Mutex,
    };

    use super::*;

    pub struct MemFileSystem {
        files: Mutex<HashMap<PathBuf, Vec<u8>>>,
        dirs: Mutex<HashSet<PathBuf>>,
    }

    impl MemFileSystem {
        pub fn new() -> Self {
            Self {
                files: Mutex::new(HashMap::new()),
                dirs: Mutex::new(HashSet::new()),
            }
        }

        pub fn add_file(&self, path: impl Into<PathBuf>, content: impl Into<Vec<u8>>) {
            let path = path.into();
            if let Some(parent) = path.parent() {
                self.add_dir(parent);
            }
            self.files.lock().unwrap().insert(path, content.into());
        }

        pub fn add_dir(&self, path: impl Into<PathBuf>) {
            let path = path.into();
            let mut current = PathBuf::new();
            for component in path.components() {
                current.push(component.as_os_str());
                self.dirs.lock().unwrap().insert(current.clone());
            }
        }
    }

    impl Default for MemFileSystem {
        fn default() -> Self {
            Self::new()
        }
    }

    impl FileSystem for MemFileSystem {
        fn read_to_string(&self, path: &Path) -> Result<String, KaizenError> {
            let files = self.files.lock().unwrap();
            files
                .get(path)
                .map(|b| String::from_utf8_lossy(b).into_owned())
                .ok_or_else(|| {
                    KaizenError::Io(std::io::Error::new(
                        std::io::ErrorKind::NotFound,
                        path.display().to_string(),
                    ))
                })
        }

        fn read_dir_paths(&self, path: &Path) -> Result<Vec<PathBuf>, KaizenError> {
            if !self.is_dir(path) {
                return Err(KaizenError::Io(std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    path.display().to_string(),
                )));
            }
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
                || self.dirs.lock().unwrap().contains(path)
        }

        fn is_dir(&self, path: &Path) -> bool {
            self.dirs.lock().unwrap().contains(path)
        }

        fn write(&self, path: &Path, content: &[u8]) -> Result<(), KaizenError> {
            if let Some(parent) = path.parent() {
                self.add_dir(parent);
            }
            self.files
                .lock()
                .unwrap()
                .insert(path.to_owned(), content.to_vec());
            Ok(())
        }

        fn create_dir_all(&self, path: &Path) -> Result<(), KaizenError> {
            self.add_dir(path);
            Ok(())
        }

        fn rename(&self, from: &Path, to: &Path) -> Result<(), KaizenError> {
            let mut files = self.files.lock().unwrap();
            let content = files.remove(from).ok_or_else(|| {
                KaizenError::Io(std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    from.display().to_string(),
                ))
            })?;
            files.insert(to.to_owned(), content);
            Ok(())
        }

        fn remove_file(&self, path: &Path) -> Result<(), KaizenError> {
            let removed = self.files.lock().unwrap().remove(path);
            removed.map(|_| ()).ok_or_else(|| {
                KaizenError::Io(std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    path.display().to_string(),
                ))
            })
        }

        fn remove_dir_all(&self, path: &Path) -> Result<(), KaizenError> {
            let mut files = self.files.lock().unwrap();
            let to_remove: Vec<_> = files
                .keys()
                .filter(|p| p.starts_with(path))
                .cloned()
                .collect();
            for p in to_remove {
                files.remove(&p);
            }
            self.dirs.lock().unwrap().retain(|p| !p.starts_with(path));
            Ok(())
        }
    }
}
