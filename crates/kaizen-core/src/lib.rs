use std::path::{Path, PathBuf};

pub mod config;
pub mod error;
pub mod feature;
pub mod feature_store;
pub mod installer;
pub mod merge;
pub mod os;
pub mod plan;

pub use config::{
    DotfilesConfig, FeatureSelection, UserConfig, UserSettings, CURRENT_SCHEMA_VERSION,
};
pub use error::KaizenError;
pub use feature::FeatureFile;
pub use feature_store::FeatureStore;
pub use installer::{Installer, Remover, UptInstaller};
pub use os::TargetOs;
pub use plan::{ConfigPlan, InstallPlan, WorkflowPlan};

pub struct KaizenEngine {
    features_dir: PathBuf,
}

impl KaizenEngine {
    pub fn new(features_dir: impl Into<PathBuf>) -> Self {
        Self {
            features_dir: features_dir.into(),
        }
    }

    pub fn load_config(&self, path: &Path) -> Result<UserConfig, KaizenError> {
        config::load(path)
    }

    pub fn default_config_path() -> PathBuf {
        dirs::config_dir()
            .or_else(|| dirs::home_dir().map(|p| p.join(".config")))
            .unwrap_or_else(|| PathBuf::from(".config"))
            .join("kaizen")
            .join("config.toml")
    }

    pub fn list_features(&self) -> Result<Vec<String>, KaizenError> {
        FeatureStore::new(&self.features_dir).list()
    }

    pub fn list_features_with_meta(&self) -> Result<Vec<(String, Option<String>)>, KaizenError> {
        let store = FeatureStore::new(&self.features_dir);
        store
            .list()?
            .into_iter()
            .map(|name| {
                let desc = store.load_optional(&name)?.and_then(|f| f.meta.description);
                Ok((name, desc))
            })
            .collect()
    }

    pub fn build_workflow_plan(
        &self,
        config: &UserConfig,
        target_os: TargetOs,
    ) -> Result<WorkflowPlan, KaizenError> {
        let store = FeatureStore::new(&self.features_dir);
        merge::build_plan(config, &store, target_os)
    }
}
