use std::path::{Path, PathBuf};
use std::sync::Arc;

pub mod backends;
pub mod chezmoi;
pub mod chezmoi_client;
pub mod config;
pub mod container;
pub mod error;
pub mod executor;
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
pub mod steel_module;
pub mod sync_backend;
pub mod toolchain;

pub use backends::{NixSyncBackend, UptSyncBackend};
pub use chezmoi::{
    read_kaizen_data, write_variant_selections, KaizenData, ModifiedFile, RemoveFilesReport,
};
pub use chezmoi_client::{ChezmoiClient, NoopChezmoiClient, SourceBackup};
pub use config::{
    DotfilesConfig, FeatureSelection, UiSettings, UserConfig, UserSettings, CURRENT_SCHEMA_VERSION,
    DEFAULT_DOTFILES_SOURCE,
};
pub use container::{ContainerCleaner, NoopContainerCleaner};
pub use error::KaizenError;
pub use executor::{NoopExecutor, ProcessCommand, ProcessExecutor, ProcessOutput};
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
    _reporter: &dyn ProgressReporter,
    chezmoi: &dyn chezmoi_client::ChezmoiClient,
    fs: &dyn FileSystem,
) -> Result<PathBuf, KaizenError> {
    if let Some(dir) = explicit {
        return Ok(dir);
    }
    if let Some(source) = chezmoi.source_path()? {
        let candidate = source
            .join(manifest::KAIZEN_DIR)
            .join(manifest::FEATURES_SUBDIR);
        if fs.is_dir(&candidate) {
            return Ok(candidate);
        }
    }
    let monorepo_candidate = PathBuf::from("dotfiles")
        .join(manifest::KAIZEN_DIR)
        .join(manifest::FEATURES_SUBDIR);
    if fs.is_dir(&monorepo_candidate) {
        return Ok(monorepo_candidate);
    }
    Err(KaizenError::FeaturesDirNotFound {
        path: PathBuf::from(manifest::KAIZEN_DIR).join(manifest::FEATURES_SUBDIR),
    })
}

/// Stub engine — feature/variant/ranking subsystems removed in steel-poc phase A.
pub struct KaizenEngine {
    fs: Arc<dyn FileSystem>,
    data_toml_path: Option<PathBuf>,
}

impl KaizenEngine {
    pub fn new(_features_dir: impl Into<PathBuf>, fs: Arc<dyn FileSystem>) -> Self {
        Self {
            fs,
            data_toml_path: None,
        }
    }

    pub fn cache_only(fs: Arc<dyn FileSystem>) -> Self {
        Self {
            fs,
            data_toml_path: None,
        }
    }

    pub fn with_nix_cache(self, _path: PathBuf) -> Self {
        self
    }

    pub fn with_data_toml_path(mut self, path: PathBuf) -> Self {
        self.data_toml_path = Some(path);
        self
    }

    pub fn load_config(&self, path: &Path) -> Result<config::UserConfig, KaizenError> {
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
        Ok(vec![])
    }

    pub fn list_features_with_meta(&self) -> Result<Vec<(String, Option<String>)>, KaizenError> {
        Ok(vec![])
    }

    pub fn build_workflow_plan(
        &self,
        config: &config::UserConfig,
        target_os: TargetOs,
    ) -> Result<WorkflowPlan, KaizenError> {
        merge::build_plan_stub(config, target_os)
    }

    pub fn list_wizard_features(&self, _experimental: bool) -> Result<Vec<()>, KaizenError> {
        Ok(vec![])
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fs::mem::MemFileSystem;

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
        fn resolve_source_root(&self, e: &Path) -> PathBuf {
            e.to_owned()
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
        fn apply(&self, _: bool) -> Result<(), KaizenError> {
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
        fn backup_source_dir(&self, p: &Path) -> Result<chezmoi_client::SourceBackup, KaizenError> {
            Ok(chezmoi_client::SourceBackup {
                backup_path: p.with_extension("bak"),
                restore_path: p.to_owned(),
            })
        }
    }

    #[test]
    fn resolve_features_dir_finds_features_in_chezmoi_source() {
        let fs = MemFileSystem::new();
        let source = PathBuf::from("/source");
        let features = source
            .join(manifest::KAIZEN_DIR)
            .join(manifest::FEATURES_SUBDIR);
        fs.add_dir(&features);
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
    fn resolve_features_dir_errors_when_source_has_no_features() {
        let fs = MemFileSystem::new();
        let result = resolve_features_dir(
            None,
            &NoopReporter,
            &SourceClient {
                source: Some(PathBuf::from("/source")),
            },
            &fs,
        );
        assert!(matches!(
            result,
            Err(KaizenError::FeaturesDirNotFound { .. })
        ));
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
