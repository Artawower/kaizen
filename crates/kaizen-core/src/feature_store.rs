use std::path::{Path, PathBuf};

use crate::{FeatureFile, KaizenError};

pub struct FeatureStore {
    dir: PathBuf,
}

impl FeatureStore {
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Self { dir: dir.into() }
    }

    pub fn list(&self) -> Result<Vec<String>, KaizenError> {
        let entries = std::fs::read_dir(&self.dir).map_err(|e| {
            if e.kind() == std::io::ErrorKind::NotFound {
                KaizenError::FeaturesDirNotFound {
                    path: self.dir.clone(),
                }
            } else {
                KaizenError::Io(e)
            }
        })?;

        let mut names = Vec::new();
        for entry in entries {
            let path = entry?.path();
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
        if !path.exists() {
            return Err(KaizenError::FeatureNotFound {
                name: name.to_owned(),
            });
        }
        self.parse(name, &path)
    }

    pub fn load_optional(&self, name: &str) -> Result<Option<FeatureFile>, KaizenError> {
        let path = self.validated_path(name)?;
        if !path.exists() {
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
        let raw = std::fs::read_to_string(path)?;
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
    use super::*;

    #[test]
    fn rejects_path_traversal() {
        let store = FeatureStore::new(PathBuf::from("/tmp"));
        assert!(matches!(
            store.load("../evil").unwrap_err(),
            KaizenError::InvalidFeatureName { .. }
        ));
    }

    #[test]
    fn rejects_nested_path() {
        let store = FeatureStore::new(PathBuf::from("/tmp"));
        assert!(matches!(
            store.load("nested/evil").unwrap_err(),
            KaizenError::InvalidFeatureName { .. }
        ));
    }

    #[test]
    fn rejects_empty_name() {
        let store = FeatureStore::new(PathBuf::from("/tmp"));
        assert!(matches!(
            store.load("").unwrap_err(),
            KaizenError::InvalidFeatureName { .. }
        ));
    }

    #[test]
    fn reports_missing_directory() {
        let store = FeatureStore::new(PathBuf::from("/nonexistent-kaizen-dir"));
        assert!(matches!(
            store.list().unwrap_err(),
            KaizenError::FeaturesDirNotFound { .. }
        ));
    }
}
