use std::path::Path;

use indexmap::IndexMap;
use serde::{Deserialize, Serialize};

use crate::KaizenError;

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct UserConfig {
    #[serde(default)]
    pub features: IndexMap<String, FeatureSelection>,

    #[serde(default)]
    pub settings: UserSettings,

    #[serde(default)]
    pub dotfiles: DotfilesConfig,
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

pub fn load(path: &Path) -> Result<UserConfig, KaizenError> {
    if !path.exists() {
        return Err(KaizenError::ConfigNotFound {
            path: path.to_owned(),
        });
    }
    let raw = std::fs::read_to_string(path)?;
    toml::from_str(&raw).map_err(|source| KaizenError::ConfigParse {
        path: path.to_owned(),
        source,
    })
}
