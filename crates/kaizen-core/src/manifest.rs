use std::path::Path;

use serde::Deserialize;

use crate::KaizenError;

pub const CURRENT_MANIFEST_VERSION: u32 = 1;
pub const KAIZEN_DIR: &str = "kaizen";
pub const FEATURES_SUBDIR: &str = "features";

#[derive(Debug, Deserialize)]
pub struct ManifestFeature {
    pub name: String,
    pub description: String,
}

#[derive(Debug, Deserialize)]
pub struct KaizenManifest {
    #[serde(default = "default_version")]
    pub schema_version: u32,

    /// Authoritative list of user-visible features.
    ///
    /// When non-empty this is the single source of truth for feature names and
    /// descriptions — used by the wizard UI and as the canonical key set for
    /// `data.toml`.  Nix `options.nix` reads the same file via
    /// `builtins.fromTOML`, so adding a feature here automatically makes it
    /// available to both kaizen and Home Manager.
    #[serde(default)]
    pub features: Vec<ManifestFeature>,
}

fn default_version() -> u32 {
    1
}

pub fn load_with(
    kaizen_dir: &Path,
    fs: &dyn crate::FileSystem,
) -> Result<KaizenManifest, KaizenError> {
    let path = kaizen_dir.join("manifest.toml");
    if !fs.exists(&path) {
        return Ok(KaizenManifest {
            schema_version: 1,
            features: vec![],
        });
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
