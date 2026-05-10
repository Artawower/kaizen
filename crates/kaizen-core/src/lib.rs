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
pub use chezmoi_client::{ChezmoiClient, NoopChezmoiClient, SourceBackup};
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
    // Monorepo dev layout: running kaizen from the repo root.
    let monorepo_candidate = PathBuf::from("dotfiles")
        .join(manifest::KAIZEN_DIR)
        .join(manifest::FEATURES_SUBDIR);
    if fs.is_dir(&monorepo_candidate) {
        return Ok(monorepo_candidate);
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{fs::mem::MemFileSystem, progress::RecordingReporter};

    struct SourceClient {
        source: Option<PathBuf>,
    }

    impl chezmoi_client::ChezmoiClient for SourceClient {
        fn managed_files(&self) -> Result<Vec<PathBuf>, KaizenError> {
            Ok(vec![])
        }

        fn locally_modified_files(&self) -> Result<Vec<PathBuf>, KaizenError> {
            Ok(vec![])
        }

        fn source_path(&self) -> Result<Option<PathBuf>, KaizenError> {
            Ok(self.source.clone())
        }
        fn raw_source_path(&self) -> Result<Option<PathBuf>, KaizenError> {
            Ok(self.source.clone())
        }
        fn pull_source(&self, _: &Path) -> Result<(), KaizenError> {
            Ok(())
        }
        fn current_remote(&self, _: &Path) -> Result<Option<String>, KaizenError> {
            Ok(None)
        }

        fn init_source(&self, _: &str) -> Result<(), KaizenError> {
            Ok(())
        }

        fn apply(&self) -> Result<(), KaizenError> {
            Ok(())
        }

        fn remove_files(
            &self,
            files: &[PathBuf],
            _: bool,
        ) -> Result<RemoveFilesReport, KaizenError> {
            Ok(RemoveFilesReport {
                removed: files.to_vec(),
                skipped: vec![],
            })
        }

        fn backup_source_dir(
            &self,
            source_dir: &Path,
        ) -> Result<chezmoi_client::SourceBackup, KaizenError> {
            Ok(chezmoi_client::SourceBackup {
                backup_path: source_dir.with_extension("bak"),
                restore_path: source_dir.to_owned(),
            })
        }
    }

    #[test]
    fn resolve_features_dir_uses_injected_filesystem_manifest() {
        let fs = MemFileSystem::new();
        let source = PathBuf::from("/source");
        let kaizen_dir = source.join(manifest::KAIZEN_DIR);
        let features = kaizen_dir.join(manifest::FEATURES_SUBDIR);
        fs.add_dir(&features);
        fs.add_file(kaizen_dir.join("manifest.toml"), "schema_version = 1");

        let result = resolve_features_dir(
            None,
            &NoopReporter,
            &SourceClient {
                source: Some(source),
            },
            &fs,
        )
        .unwrap();

        assert_eq!(result, features);
    }

    #[test]
    fn resolve_features_dir_warns_and_falls_back_when_source_has_no_features() {
        let fs = MemFileSystem::new();
        let reporter = RecordingReporter::new();

        let result = resolve_features_dir(
            None,
            &reporter,
            &SourceClient {
                source: Some(PathBuf::from("/source")),
            },
            &fs,
        )
        .unwrap();

        assert_eq!(result, PathBuf::from("features"));
        assert_eq!(
            reporter.warnings(),
            vec!["kaizen/features not found in chezmoi source — using built-in features"]
        );
    }

    #[test]
    fn resolve_features_dir_uses_monorepo_layout_when_no_chezmoi_source() {
        let fs = MemFileSystem::new();
        let monorepo_features = PathBuf::from("dotfiles")
            .join(manifest::KAIZEN_DIR)
            .join(manifest::FEATURES_SUBDIR);
        fs.add_dir(&monorepo_features);

        let result =
            resolve_features_dir(None, &NoopReporter, &SourceClient { source: None }, &fs).unwrap();

        assert_eq!(result, monorepo_features);
    }
}
