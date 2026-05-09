use std::path::Path;

use indexmap::IndexMap;
use serde::{Deserialize, Serialize};

use crate::KaizenError;

pub const CURRENT_SCHEMA_VERSION: u32 = 1;
pub const DEFAULT_DOTFILES_SOURCE: &str = "https://github.com/Artawower/kaizen-dotfiles";

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct UserConfig {
    #[serde(default)]
    pub schema_version: u32,

    #[serde(default)]
    pub features: IndexMap<String, FeatureSelection>,

    #[serde(default)]
    pub settings: UserSettings,

    #[serde(default)]
    pub dotfiles: DotfilesConfig,
}

impl UserConfig {
    pub fn is_schema_outdated(&self) -> bool {
        self.schema_version < CURRENT_SCHEMA_VERSION
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct FeatureSelection {
    pub enabled: bool,

    #[serde(default)]
    pub disabled_atoms: Vec<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct UserSettings {
    pub layout: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct DotfilesConfig {
    pub backend: Option<String>,
    pub source: Option<String>,
}

pub fn load_with(path: &Path, fs: &dyn crate::FileSystem) -> Result<UserConfig, KaizenError> {
    if !fs.exists(path) {
        return Err(KaizenError::ConfigNotFound {
            path: path.to_owned(),
        });
    }
    let raw = fs.read_to_string(path)?;
    toml::from_str(&raw).map_err(|source| KaizenError::ConfigParse {
        path: path.to_owned(),
        source,
    })
}
