use std::path::{Path, PathBuf};

pub mod backends;
pub mod chezmoi;
pub mod config;
pub mod error;
pub mod feature;
pub mod feature_store;
pub mod hooks;
pub mod installer;
pub mod manifest;
pub mod merge;
pub mod os;
pub mod plan;
pub mod process;
pub mod progress;
pub mod sync_backend;

pub use backends::detect::detect_backend;
pub use backends::{NixSyncBackend, UptSyncBackend};
pub use chezmoi::{ModifiedFile, RemoveFilesReport};
pub use config::{
    DotfilesConfig, FeatureSelection, UserConfig, UserSettings, CURRENT_SCHEMA_VERSION,
    DEFAULT_DOTFILES_SOURCE,
};
pub use error::KaizenError;
pub use feature::FeatureFile;
pub use feature_store::FeatureStore;
pub use hooks::{HookRunner, ShellHookRunner};
pub use installer::{Installer, Remover, Updater, UptInstaller};
pub use os::{PackageManagerKind, TargetOs};
pub use plan::{ConfigPlan, HookPlan, InstallPlan, WorkflowPlan};
pub use progress::{NoopReporter, ProgressReporter};
pub use sync_backend::{
    ApplyReport, CleanOpts, CleanReport, InstallReport, SyncBackend, SyncOpts, SyncPreview,
    SyncReport, SyncStep, UpdateOpts, UpdateReport,
};

pub fn resolve_features_dir(
    explicit: Option<PathBuf>,
    reporter: &dyn ProgressReporter,
) -> Result<PathBuf, KaizenError> {
    if let Some(dir) = explicit {
        return Ok(dir);
    }
    if let Some(source) = chezmoi::standalone_source_dir()? {
        let kaizen_dir = source.join(manifest::KAIZEN_DIR);
        let candidate = kaizen_dir.join(manifest::FEATURES_SUBDIR);
        if candidate.is_dir() {
            let m = manifest::load(&kaizen_dir)?;
            manifest::validate(&m)?;
            return Ok(candidate);
        }
        reporter.warn("kaizen/features not found in chezmoi source — using built-in features");
    }
    Ok(PathBuf::from("features"))
}

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
