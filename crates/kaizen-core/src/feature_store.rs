use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::{FeatureFile, FileSystem, KaizenError};

pub struct FeatureStore {
    dir: PathBuf,
    fs: Arc<dyn FileSystem>,
}

impl FeatureStore {
    pub fn new(dir: impl Into<PathBuf>, fs: Arc<dyn FileSystem>) -> Self {
        Self {
            dir: dir.into(),
            fs,
        }
    }

    pub fn list(&self) -> Result<Vec<String>, KaizenError> {
        let entries = self.fs.read_dir_paths(&self.dir).map_err(|e| {
            if let KaizenError::Io(ref io_err) = e {
                if io_err.kind() == std::io::ErrorKind::NotFound {
                    return KaizenError::FeaturesDirNotFound {
                        path: self.dir.clone(),
                    };
                }
            }
            e
        })?;

        let mut names = Vec::new();
        for path in entries {
            if path.extension().and_then(|s| s.to_str()) != Some("toml") {
                continue;
            }
            let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else {
                continue;
            };
            if is_valid_feature_name(stem) {
                names.push(stem.to_owned());
            }
        }
        names.sort();
        Ok(names)
    }

    pub fn load(&self, name: &str) -> Result<FeatureFile, KaizenError> {
        let path = self.validated_path(name)?;
        if !self.fs.exists(&path) {
            return Err(KaizenError::FeatureNotFound {
                name: name.to_owned(),
            });
        }
        self.parse(name, &path)
    }

    pub fn load_optional(&self, name: &str) -> Result<Option<FeatureFile>, KaizenError> {
        let path = self.validated_path(name)?;
        if !self.fs.exists(&path) {
            return Ok(None);
        }
        self.parse(name, &path).map(Some)
    }

    fn validated_path(&self, name: &str) -> Result<PathBuf, KaizenError> {
        if name.is_empty() || !is_valid_feature_name(name) {
            return Err(KaizenError::InvalidFeatureName {
                name: name.to_owned(),
            });
        }
        Ok(self.dir.join(format!("{name}.toml")))
    }

    fn parse(&self, name: &str, path: &Path) -> Result<FeatureFile, KaizenError> {
        let raw = self.fs.read_to_string(path)?;
        toml::from_str(&raw).map_err(|source| KaizenError::FeatureParse {
            name: name.to_owned(),
            source,
        })
    }
}

fn is_valid_feature_name(name: &str) -> bool {
    !name.is_empty()
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;
    use crate::fs::mem::MemFileSystem;

    fn mem_store(files: &[(&str, &str)]) -> FeatureStore {
        let dir = PathBuf::from("/features");
        let fs = MemFileSystem::new();
        for (name, content) in files {
            fs.add_file(dir.join(format!("{name}.toml")), content.as_bytes());
        }
        FeatureStore::new(dir, Arc::new(fs))
    }

    #[test]
    fn rejects_path_traversal() {
        let store = FeatureStore::new(PathBuf::from("/tmp"), Arc::new(MemFileSystem::new()));
        assert!(matches!(
            store.load("../evil").unwrap_err(),
            KaizenError::InvalidFeatureName { .. }
        ));
    }

    #[test]
    fn rejects_nested_path() {
        let store = FeatureStore::new(PathBuf::from("/tmp"), Arc::new(MemFileSystem::new()));
        assert!(matches!(
            store.load("nested/evil").unwrap_err(),
            KaizenError::InvalidFeatureName { .. }
        ));
    }

    #[test]
    fn rejects_empty_name() {
        let store = FeatureStore::new(PathBuf::from("/tmp"), Arc::new(MemFileSystem::new()));
        assert!(matches!(
            store.load("").unwrap_err(),
            KaizenError::InvalidFeatureName { .. }
        ));
    }

    #[test]
    fn reports_missing_directory() {
        let store = FeatureStore::new(
            PathBuf::from("/nonexistent-kaizen-dir"),
            Arc::new(MemFileSystem::new()),
        );
        assert!(matches!(
            store.list().unwrap_err(),
            KaizenError::FeaturesDirNotFound { .. }
        ));
    }

    #[test]
    fn lists_toml_files_from_mem_fs() {
        let store = mem_store(&[("core", "[meta]\n"), ("rust", "[meta]\n")]);
        let names = store.list().unwrap();
        assert_eq!(names, vec!["core", "rust"]);
    }

    #[test]
    fn load_optional_returns_none_for_missing() {
        let store = mem_store(&[]);
        assert!(store.load_optional("missing").unwrap().is_none());
    }

    #[test]
    fn load_optional_parses_present_file() {
        let store = mem_store(&[("core", "[meta]\ndescription = \"test\"\n")]);
        let feature = store.load_optional("core").unwrap().unwrap();
        assert_eq!(feature.meta.description.as_deref(), Some("test"));
    }
}
