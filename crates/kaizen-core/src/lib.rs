use std::path::{Path, PathBuf};
use std::sync::Arc;

pub mod backends;
pub mod chezmoi;
pub mod chezmoi_client;
pub mod config;
pub mod container;
pub mod error;
pub mod executor;
pub mod feature;
pub mod feature_store;
pub mod fs;
pub mod hooks;
pub mod installer;
pub mod manifest;
pub mod merge;
pub mod os;
pub mod paths;
pub mod plan;
pub mod progress;
pub mod runtime;
pub mod setup;
pub mod sync_backend;
pub mod toolchain;

pub use backends::{NixSyncBackend, UptSyncBackend};
pub use chezmoi::{ModifiedFile, RemoveFilesReport};
pub use chezmoi_client::{ChezmoiClient, NoopChezmoiClient};
pub use config::{
    DotfilesConfig, FeatureSelection, UserConfig, UserSettings, CURRENT_SCHEMA_VERSION,
    DEFAULT_DOTFILES_SOURCE,
};
pub use container::{ContainerCleaner, NoopContainerCleaner};
pub use error::KaizenError;
pub use executor::{NoopExecutor, ProcessCommand, ProcessExecutor, ProcessOutput};
pub use feature::FeatureFile;
pub use feature_store::FeatureStore;
pub use fs::FileSystem;
pub use hooks::HookRunner;
pub use installer::{Installer, PackageInstaller, Remover, Updater};
pub use os::{PackageManagerKind, TargetOs};
pub use paths::PathProvider;
pub use plan::{ConfigPlan, HookPlan, InstallPlan, WorkflowPlan};
pub use progress::{NoopReporter, ProgressReporter};
pub use runtime::Runtime;
pub use setup::{
    render_config, resolve_features_dir_from_source, BootstrapStatus, ChezmoiBootstrapper,
};
pub use sync_backend::{
    ApplyBackend, ApplyReport, CleanBackend, CleanOpts, CleanReport, InstallBackend, InstallReport,
    PostApplyBackend, PreviewBackend, SyncBackend, SyncOpts, SyncPreview, SyncReport, SyncStep,
    UpdateBackend, UpdateOpts, UpdateReport,
};
pub use toolchain::{DevToolsManager, NoopDevTools, ToolStep};

pub fn resolve_features_dir(
    explicit: Option<PathBuf>,
    reporter: &dyn ProgressReporter,
    chezmoi: &dyn chezmoi_client::ChezmoiClient,
    fs: &dyn FileSystem,
) -> Result<PathBuf, KaizenError> {
    if let Some(dir) = explicit {
        return Ok(dir);
    }
    if let Some(source) = chezmoi.source_path()? {
        let kaizen_dir = source.join(manifest::KAIZEN_DIR);
        let candidate = kaizen_dir.join(manifest::FEATURES_SUBDIR);
        if fs.is_dir(&candidate) {
            let m = manifest::load_with(&kaizen_dir, fs)?;
            manifest::validate(&m)?;
            return Ok(candidate);
        }
        reporter.warn("kaizen/features not found in chezmoi source — using built-in features");
    }
    Ok(PathBuf::from("features"))
}

pub struct KaizenEngine {
    features_dir: PathBuf,
    fs: Arc<dyn FileSystem>,
}

impl KaizenEngine {
    pub fn new(features_dir: impl Into<PathBuf>, fs: Arc<dyn FileSystem>) -> Self {
        Self {
            features_dir: features_dir.into(),
            fs,
        }
    }

    pub fn load_config(&self, path: &Path) -> Result<UserConfig, KaizenError> {
        config::load_with(path, self.fs.as_ref())
    }

    pub fn default_config_path(paths: &dyn PathProvider) -> PathBuf {
        paths
            .config_dir()
            .unwrap_or_else(|| PathBuf::from(".config"))
            .join("kaizen")
            .join("config.toml")
    }

    pub fn list_features(&self) -> Result<Vec<String>, KaizenError> {
        FeatureStore::new(&self.features_dir, Arc::clone(&self.fs)).list()
    }

    pub fn list_features_with_meta(&self) -> Result<Vec<(String, Option<String>)>, KaizenError> {
        let store = FeatureStore::new(&self.features_dir, Arc::clone(&self.fs));
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
        let store = FeatureStore::new(&self.features_dir, Arc::clone(&self.fs));
        merge::build_plan(config, &store, target_os)
    }
}
