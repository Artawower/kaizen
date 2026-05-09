use std::path::Path;

use serde::Deserialize;

use crate::KaizenError;

pub const CURRENT_MANIFEST_VERSION: u32 = 1;
pub const KAIZEN_DIR: &str = "kaizen";
pub const FEATURES_SUBDIR: &str = "features";

#[derive(Debug, Deserialize)]
pub struct KaizenManifest {
    #[serde(default = "default_version")]
    pub schema_version: u32,
}

fn default_version() -> u32 {
    1
}

pub fn load(kaizen_dir: &Path) -> Result<KaizenManifest, KaizenError> {
    load_with(kaizen_dir, &crate::StdFileSystem)
}

pub fn load_with(
    kaizen_dir: &Path,
    fs: &dyn crate::FileSystem,
) -> Result<KaizenManifest, KaizenError> {
    let path = kaizen_dir.join("manifest.toml");
    if !fs.exists(&path) {
        return Ok(KaizenManifest { schema_version: 1 });
    }
    let raw = fs.read_to_string(&path)?;
    toml::from_str(&raw).map_err(|source| KaizenError::ManifestParse { path, source })
}

pub fn validate(manifest: &KaizenManifest) -> Result<(), KaizenError> {
    if manifest.schema_version > CURRENT_MANIFEST_VERSION {
        return Err(KaizenError::ManifestSchemaTooNew {
            found: manifest.schema_version,
            supported: CURRENT_MANIFEST_VERSION,
        });
    }
    Ok(())
}
