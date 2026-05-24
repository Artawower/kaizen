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
pub mod nix_feature_cache;
pub mod os;
pub mod paths;
pub mod plan;
pub mod progress;
pub mod rank;
pub mod runtime;
pub mod setup;
pub mod sync_backend;
pub mod toolchain;
pub mod variants;

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
pub use feature::FeatureFile;
pub use feature_store::FeatureStore;
pub use fs::FileSystem;
pub use hooks::HookRunner;
pub use installer::{Installer, PackageInstaller, Remover, Updater};
pub use nix_feature_cache::{BumpWorkflow, OnFailure, UpdateHook};
pub use os::{PackageManagerKind, TargetOs};
pub use paths::PathProvider;
pub use plan::{ConfigPlan, HookPlan, InstallPlan, WorkflowPlan};
pub use progress::{NoopReporter, ProgressReporter};
pub use rank::{Alternative, Criterion, DecisionMatrix, Direction, Ranked, Ranking};
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
pub use variants::{
    discover_variants, Slot, Stability, VariantChoice, VariantManifest, VariantProvides,
    VariantRequires, VariantResolver, WizardFeature, WizardFeatureSlot,
};

/// Execution order for bump and update workflows.
///
/// dev/toolchain features run first so tools like `pi` are upgraded
/// before dependent AI extension updates (`pi update --extensions`).
///
/// Order: dev → system → other → ai
fn category_order(category: &str) -> usize {
    match category {
        "dev" => 0,
        "system" => 1,
        "ai" => 100,
        _ => 50,
    }
}

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
    // Monorepo dev layout: running kaizen from the repo root.
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

pub struct KaizenEngine {
    /// Directory containing `*.toml` feature manifests (for `FeatureStore`).
    features_dir: Option<PathBuf>,
    /// Root of the variants tree: `<repo>/features/<feature>/variants/*/variant.toml`.
    /// Separate from `features_dir` because features and variants live in different repo paths.
    variants_dir: Option<PathBuf>,
    fs: Arc<dyn FileSystem>,
    nix_cache_path: Option<PathBuf>,
    /// Path to `~/.config/kaizen/data.toml`.
    data_toml_path: Option<PathBuf>,
}

impl KaizenEngine {
    pub fn new(features_dir: impl Into<PathBuf>, fs: Arc<dyn FileSystem>) -> Self {
        Self {
            features_dir: Some(features_dir.into()),
            variants_dir: None,
            fs,
            nix_cache_path: None,
            data_toml_path: None,
        }
    }

    /// Engine that reads exclusively from the Nix feature cache.
    /// Returns `FeaturesDirNotFound` if the cache is unavailable.
    pub fn cache_only(fs: Arc<dyn FileSystem>) -> Self {
        Self {
            features_dir: None,
            variants_dir: None,
            fs,
            nix_cache_path: None,
            data_toml_path: None,
        }
    }

    pub fn with_nix_cache(mut self, path: PathBuf) -> Self {
        self.nix_cache_path = Some(path);
        self
    }

    pub fn with_data_toml_path(mut self, path: PathBuf) -> Self {
        self.data_toml_path = Some(path);
        self
    }

    pub fn with_variants_dir(mut self, path: PathBuf) -> Self {
        self.variants_dir = Some(path);
        self
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

    fn feature_store(&self) -> Result<FeatureStore, KaizenError> {
        let dir = self
            .features_dir
            .as_deref()
            .ok_or_else(|| KaizenError::FeaturesDirNotFound {
                path: PathBuf::from(manifest::KAIZEN_DIR).join(manifest::FEATURES_SUBDIR),
            })?;
        Ok(FeatureStore::new(dir, Arc::clone(&self.fs)))
    }

    pub fn list_features(&self) -> Result<Vec<String>, KaizenError> {
        self.feature_store()?.list()
    }

    /// Returns `(name, description)` pairs.
    ///
    /// Priority:
    /// 1. `feature-meta.json` generated by home-manager activation (Nix machines).
    /// 2. Scanning `features/*.toml` — fresh machines / non-Nix fallback.
    pub fn list_features_with_meta(&self) -> Result<Vec<(String, Option<String>)>, KaizenError> {
        if let Some(ref cache_path) = self.nix_cache_path {
            if let Some(map) = nix_feature_cache::load(cache_path, self.fs.as_ref())? {
                return Ok(map
                    .into_iter()
                    .map(|(name, meta)| {
                        let desc = Some(meta.description).filter(|d| !d.is_empty());
                        (name, desc)
                    })
                    .collect());
            }
        }
        let store = self.feature_store()?;
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
        // Feature names used only to scope the install plan.
        // For the Nix backend packages come from home-manager, so an empty
        // list is safe — sync still runs chezmoi + home-manager correctly.
        let all_names: Vec<String> = if let Some(ref cache_path) = self.nix_cache_path {
            if let Some(map) = nix_feature_cache::load(cache_path, self.fs.as_ref())? {
                map.into_keys().collect()
            } else {
                self.feature_store()
                    .and_then(|s| s.list())
                    .unwrap_or_default()
            }
        } else {
            self.feature_store()
                .and_then(|s| s.list())
                .unwrap_or_default()
        };
        let store = self.feature_store().unwrap_or_else(|_| {
            FeatureStore::new(
                PathBuf::from(manifest::KAIZEN_DIR).join(manifest::FEATURES_SUBDIR),
                Arc::clone(&self.fs),
            )
        });
        let mut plan = merge::build_plan(config, &store, &all_names, target_os)?;
        // Append post_apply hooks from the active variant for each slot.
        if let Some(ref variants_dir) = self.variants_dir {
            let os = TargetOs::detect();
            let current_selections = self.current_variant_selections()?;
            let variants = discover_variants(variants_dir, self.fs.as_ref())?;
            let resolver = VariantResolver::new(variants);
            for slot in resolver.list_slots() {
                if let Some(variant) = resolver.effective(&slot, &os, &current_selections) {
                    plan.hook_plan
                        .post_apply
                        .extend(variant.hooks.post_apply.iter().cloned());
                }
            }
        }
        Ok(plan)
    }

    /// Return update hooks declared by enabled features in `config`.
    ///
    /// Reads from the Nix feature cache (`feature-meta.json`). Returns an
    /// empty list when the cache is absent (fresh machine / non-Nix backend).
    /// Results are sorted by category order: dev → system → other → ai.
    pub fn update_hooks_for_enabled_features(
        &self,
        config: &UserConfig,
    ) -> Result<Vec<nix_feature_cache::UpdateHook>, KaizenError> {
        let Some(ref cache_path) = self.nix_cache_path else {
            return Ok(vec![]);
        };
        let Some(meta) = nix_feature_cache::load(cache_path, self.fs.as_ref())? else {
            return Ok(vec![]);
        };
        let mut entries: Vec<(String, String, Vec<nix_feature_cache::UpdateHook>)> = config
            .features
            .iter()
            .filter(|(_, sel)| sel.enabled)
            .filter_map(|(name, _)| {
                meta.get(name.as_str()).map(|m| {
                    let hooks = if !m.update.is_empty() {
                        m.update.clone()
                    } else {
                        m.update_hooks.clone()
                    };
                    (name.clone(), m.category.clone(), hooks)
                })
            })
            .collect();
        entries.sort_by_key(|(name, cat, _)| (category_order(cat), name.clone()));
        Ok(entries
            .into_iter()
            .flat_map(|(_, _, hooks)| hooks)
            .collect())
    }

    /// Return bump workflows declared by enabled features in `config`.
    ///
    /// Reads from the Nix feature cache (`feature-meta.json`). Features with an
    /// empty bump workflow (no `before`, `run`, or `capture`) are skipped.
    /// Results are sorted by category order: dev → system → other → ai.
    /// Returns an empty list when the cache is absent.
    pub fn bump_for_enabled_features(
        &self,
        config: &UserConfig,
    ) -> Result<Vec<(String, nix_feature_cache::BumpWorkflow)>, KaizenError> {
        let Some(ref cache_path) = self.nix_cache_path else {
            return Ok(vec![]);
        };
        let Some(meta) = nix_feature_cache::load(cache_path, self.fs.as_ref())? else {
            return Ok(vec![]);
        };
        let mut bumps: Vec<(String, String, nix_feature_cache::BumpWorkflow)> = config
            .features
            .iter()
            .filter(|(_, sel)| sel.enabled)
            .filter_map(|(name, _)| {
                meta.get(name.as_str()).and_then(|m| {
                    let bump = m.bump.clone();
                    if bump.is_empty() {
                        None
                    } else {
                        Some((name.clone(), m.category.clone(), bump))
                    }
                })
            })
            .collect();
        bumps.sort_by_key(|(name, cat, _)| (category_order(cat), name.clone()));
        Ok(bumps
            .into_iter()
            .map(|(name, _, bump)| (name, bump))
            .collect())
    }

    /// Build the unified feature+variants list for the wizard screen.
    ///
    /// When `include_experimental=false` every feature has `slot = None` (E=off flat list).
    /// When `include_experimental=true` features that have OS-compatible variants get
    /// `slot = Some(WizardFeatureSlot { choices, selected_id })` (E=on inline variant rows).
    pub fn list_wizard_features(
        &self,
        include_experimental: bool,
    ) -> Result<Vec<WizardFeature>, KaizenError> {
        let feature_meta = self.list_features_with_meta()?;

        let enabled_map: std::collections::BTreeMap<String, bool> =
            if let Some(ref path) = self.data_toml_path {
                read_kaizen_data(path, self.fs.as_ref())?.features
            } else {
                Default::default()
            };

        if !include_experimental {
            return Ok(feature_meta
                .into_iter()
                .map(|(id, desc)| WizardFeature {
                    enabled: enabled_map.get(&id).copied().unwrap_or(true),
                    description: desc.unwrap_or_default(),
                    id,
                    slot: None,
                })
                .collect());
        }

        // Build a per-feature-name slot index from the variants dir.
        let slot_by_feature: std::collections::HashMap<String, WizardFeatureSlot> =
            if let Some(ref variants_dir) = self.variants_dir {
                let os = TargetOs::detect();
                let selections = self.current_variant_selections()?;
                let all_variants = discover_variants(variants_dir, self.fs.as_ref())?;
                let resolver = VariantResolver::new(all_variants);
                resolver
                    .list_slots()
                    .into_iter()
                    .filter_map(|slot_fqn| {
                        let feature_name =
                            slot_fqn.split('.').next().unwrap_or(&slot_fqn).to_owned();
                        let all = resolver.list_variants(&slot_fqn);
                        // Filter by OS only — stability is not filtered here; UI handles E.
                        let candidates = resolver.filter_by_os(&os, all);
                        if candidates.is_empty() {
                            return None;
                        }
                        let mut choices: Vec<VariantChoice> = candidates
                            .iter()
                            .map(|v| VariantChoice {
                                id: v.id.clone(),
                                title: v.title.clone().unwrap_or_else(|| v.id.clone()),
                                stability: v.stability.clone(),
                                is_default: v.default,
                            })
                            .collect();
                        // stable-first, lexicographic within same stability
                        choices.sort_by_key(|c| {
                            let ord: u8 = if c.stability == Stability::Stable {
                                0
                            } else {
                                1
                            };
                            (ord, c.id.clone())
                        });
                        let selected_id = selections
                            .get(&slot_fqn)
                            .cloned()
                            .or_else(|| resolver.default_for(&slot_fqn, &os).map(|v| v.id.clone()));
                        Some((
                            feature_name,
                            WizardFeatureSlot {
                                slot_fqn,
                                choices,
                                selected_id,
                            },
                        ))
                    })
                    .collect()
            } else {
                Default::default()
            };

        Ok(feature_meta
            .into_iter()
            .map(|(id, desc)| {
                let slot = slot_by_feature.get(&id).cloned();
                WizardFeature {
                    enabled: enabled_map.get(&id).copied().unwrap_or(true),
                    description: desc.unwrap_or_default(),
                    id,
                    slot,
                }
            })
            .collect())
    }

    /// Read the current `[variants]` block from `data.toml`.
    /// Returns an empty map when `data_toml_path` is unset or the file does not exist.
    pub fn current_variant_selections(
        &self,
    ) -> Result<std::collections::BTreeMap<String, String>, KaizenError> {
        let Some(ref path) = self.data_toml_path else {
            return Ok(std::collections::BTreeMap::new());
        };
        let data = read_kaizen_data(path, self.fs.as_ref())?;
        Ok(data.variants)
    }

    /// Replace the `[variants]` block in `data.toml` with `selections`.
    /// All other keys are preserved. Requires `data_toml_path` to be set.
    pub fn apply_variant_selections(
        &self,
        selections: std::collections::BTreeMap<String, String>,
    ) -> Result<(), KaizenError> {
        let path = self
            .data_toml_path
            .as_deref()
            .ok_or(KaizenError::HomeDirUnavailable)?;
        write_variant_selections(path, &selections, self.fs.as_ref())
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
        fn pull_source(&self, _: &Path) -> Result<(), KaizenError> {
            Ok(())
        }
        fn current_remote(&self, _: &Path) -> Result<Option<String>, KaizenError> {
            Ok(None)
        }

        fn init_source(&self, _: &str) -> Result<(), KaizenError> {
            Ok(())
        }

        fn apply(&self, _force: bool) -> Result<(), KaizenError> {
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
    fn list_features_with_meta_reads_from_feature_store() {
        let fs = Arc::new(MemFileSystem::new());
        let features_dir = PathBuf::from("/kaizen/features");
        fs.add_dir(&features_dir);
        fs.add_file(
            features_dir.join("core.toml"),
            "[meta]\ndescription = \"core CLI tools\"",
        );
        fs.add_file(
            features_dir.join("vcs.toml"),
            "[meta]\ndescription = \"version control tooling\"",
        );
        let engine = KaizenEngine::new(features_dir, fs);
        let meta = engine.list_features_with_meta().unwrap();
        assert_eq!(
            meta,
            vec![
                ("core".to_owned(), Some("core CLI tools".to_owned())),
                ("vcs".to_owned(), Some("version control tooling".to_owned())),
            ]
        );
    }

    #[test]
    fn cache_only_build_workflow_plan_without_cache_returns_empty_plan() {
        let fs = Arc::new(MemFileSystem::new());
        let engine = KaizenEngine::cache_only(fs);
        let config: UserConfig = toml::from_str("").unwrap();
        let plan = engine
            .build_workflow_plan(&config, TargetOs::Linux)
            .unwrap();
        assert!(plan.install_plan.programs.is_empty());
    }

    #[test]
    fn cache_only_build_workflow_plan_with_valid_cache_returns_empty_plan() {
        let fs = Arc::new(MemFileSystem::new());
        let cache = PathBuf::from("/cache/feature-meta.json");
        fs.add_file(
            &cache,
            r#"{"core":{"description":"Core","category":"system"}}""}"#.trim_end_matches("\"\"}"),
        );
        // cache loads, plan builds without programs (no feature toml files)
        let engine = KaizenEngine::cache_only(fs).with_nix_cache(cache);
        let config: UserConfig = toml::from_str("").unwrap();
        let plan = engine
            .build_workflow_plan(&config, TargetOs::Linux)
            .unwrap();
        assert!(plan.install_plan.programs.is_empty());
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

    // ── engine variant methods ──────────────────────────────────────────────

    fn make_variant_files(fs: &MemFileSystem, features_dir: &Path) {
        let tiling = features_dir.join("tiling");
        fs.add_dir(&tiling);
        fs.add_file(
            tiling.join("feature.toml"),
            "title = \"Tiling WM\"\n[[slots]]\nid = \"wm\"\ndescription = \"Window manager\"\n",
        );
        let variants_dir = tiling.join("variants");
        fs.add_dir(&variants_dir);
        let yabai = variants_dir.join("yabai");
        fs.add_dir(&yabai);
        fs.add_file(
            yabai.join("variant.toml"),
            "id = \"yabai\"\nslot = \"tiling.wm\"\nstability = \"stable\"\nplatforms = [\"darwin\"]\ndefault = true\n",
        );
        let aerospace = variants_dir.join("aerospace");
        fs.add_dir(&aerospace);
        fs.add_file(
            aerospace.join("variant.toml"),
            "id = \"aerospace\"\nslot = \"tiling.wm\"\nstability = \"experimental\"\nplatforms = [\"darwin\"]\ndefault = false\n",
        );
    }

    #[test]
    fn engine_current_variant_selections_returns_empty_when_no_data_file() {
        let fs = Arc::new(MemFileSystem::new());
        let features_dir = PathBuf::from("/features");
        fs.add_dir(&features_dir);
        let engine = KaizenEngine::new(features_dir, fs);
        let sel = engine.current_variant_selections().unwrap();
        assert!(sel.is_empty());
    }

    #[test]
    fn engine_apply_and_read_variant_selections() {
        let fs = Arc::new(MemFileSystem::new());
        let data_path = PathBuf::from("/kaizen/data.toml");
        fs.add_file(&data_path, "layout = \"qwerty\"\n");
        let features_dir = PathBuf::from("/features");
        fs.add_dir(&features_dir);
        let engine = KaizenEngine::new(features_dir, Arc::clone(&fs) as Arc<dyn FileSystem>)
            .with_data_toml_path(data_path.clone());

        let mut sel = std::collections::BTreeMap::new();
        sel.insert("tiling.wm".to_owned(), "aerospace".to_owned());
        engine.apply_variant_selections(sel.clone()).unwrap();

        let read_back = engine.current_variant_selections().unwrap();
        assert_eq!(read_back, sel);
    }

    #[test]
    fn engine_apply_variant_selections_preserves_other_keys() {
        let fs = Arc::new(MemFileSystem::new());
        let data_path = PathBuf::from("/kaizen/data.toml");
        fs.add_file(&data_path, "layout = \"colemak\"\nusername = \"alice\"\n");
        let features_dir = PathBuf::from("/features");
        fs.add_dir(&features_dir);
        let engine = KaizenEngine::new(features_dir, Arc::clone(&fs) as Arc<dyn FileSystem>)
            .with_data_toml_path(data_path.clone());

        let mut sel = std::collections::BTreeMap::new();
        sel.insert("tiling.wm".to_owned(), "yabai".to_owned());
        engine.apply_variant_selections(sel).unwrap();

        let raw = fs.read_to_string(&data_path).unwrap();
        assert!(raw.contains("layout = \"colemak\""), "layout preserved");
        assert!(raw.contains("username = \"alice\""), "username preserved");
        assert!(raw.contains("\"tiling.wm\" = \"yabai\""), "variant written");
    }

    #[test]
    fn engine_apply_variant_selections_replaces_existing_variants() {
        let fs = Arc::new(MemFileSystem::new());
        let data_path = PathBuf::from("/kaizen/data.toml");
        fs.add_file(
            &data_path,
            "layout = \"qwerty\"\n[variants]\n\"tiling.wm\" = \"aerospace\"\n",
        );
        let features_dir = PathBuf::from("/features");
        fs.add_dir(&features_dir);
        let engine = KaizenEngine::new(features_dir, Arc::clone(&fs) as Arc<dyn FileSystem>)
            .with_data_toml_path(data_path.clone());

        // Reset: pass empty selections
        engine
            .apply_variant_selections(std::collections::BTreeMap::new())
            .unwrap();

        let raw = fs.read_to_string(&data_path).unwrap();
        assert!(
            !raw.contains("aerospace"),
            "old selection should be removed"
        );
        assert!(
            !raw.contains("[variants]"),
            "empty variants section removed"
        );
    }

    #[test]
    fn wizard_features_no_experimental_all_slots_none() {
        let fs = Arc::new(MemFileSystem::new());
        let variants_dir = PathBuf::from("/variants");
        fs.add_dir(&variants_dir);
        make_variant_files(&fs, &variants_dir);
        let features_dir = PathBuf::from("/feats");
        fs.add_dir(&features_dir);
        fs.add_file(
            features_dir.join("tiling.toml"),
            "[meta]\ndescription = \"Tiling WM\"\n",
        );
        let engine = KaizenEngine::new(features_dir, Arc::clone(&fs) as Arc<dyn FileSystem>)
            .with_variants_dir(variants_dir);
        let features = engine.list_wizard_features(false).unwrap();
        assert_eq!(features.len(), 1);
        assert!(features[0].slot.is_none(), "E=off → slot = None");
    }

    #[test]
    fn wizard_features_with_experimental_tiling_gets_slot() {
        let fs = Arc::new(MemFileSystem::new());
        let variants_dir = PathBuf::from("/variants");
        fs.add_dir(&variants_dir);
        make_variant_files(&fs, &variants_dir);
        let features_dir = PathBuf::from("/feats");
        fs.add_dir(&features_dir);
        fs.add_file(
            features_dir.join("tiling.toml"),
            "[meta]\ndescription = \"Tiling WM\"\n",
        );
        let engine = KaizenEngine::new(features_dir, Arc::clone(&fs) as Arc<dyn FileSystem>)
            .with_variants_dir(variants_dir);
        let features = engine.list_wizard_features(true).unwrap();
        assert_eq!(features.len(), 1);
        let slot = features[0].slot.as_ref().expect("E=on → slot present");
        assert_eq!(slot.slot_fqn, "tiling.wm");
        assert_eq!(slot.choices.len(), 2);
        assert_eq!(slot.choices[0].id, "yabai", "stable first");
        assert_eq!(slot.choices[1].id, "aerospace");
    }

    #[test]
    fn wizard_features_no_variants_dir_all_slots_none() {
        let fs = Arc::new(MemFileSystem::new());
        let features_dir = PathBuf::from("/feats");
        fs.add_dir(&features_dir);
        fs.add_file(
            features_dir.join("core.toml"),
            "[meta]\ndescription = \"Core\"\n",
        );
        let engine = KaizenEngine::new(features_dir, Arc::clone(&fs) as Arc<dyn FileSystem>);
        let features = engine.list_wizard_features(true).unwrap();
        assert_eq!(features.len(), 1);
        assert!(features[0].slot.is_none(), "no variants_dir → slot = None");
    }

    #[test]
    fn wizard_features_platform_filter_linux_absent_on_darwin() {
        // komorebi is linux-only — should not appear in choices on darwin
        let fs = Arc::new(MemFileSystem::new());
        let variants_dir = PathBuf::from("/variants");
        fs.add_dir(&variants_dir);
        // Add tiling with yabai (darwin) + komorebi (linux)
        let tiling = variants_dir.join("tiling");
        fs.add_dir(&tiling);
        fs.add_file(
            tiling.join("feature.toml"),
            "title = \"Tiling\"\n[[slots]]\nid=\"wm\"\n",
        );
        let vdir = tiling.join("variants");
        fs.add_dir(&vdir);
        let yabai = vdir.join("yabai");
        fs.add_dir(&yabai);
        fs.add_file(yabai.join("variant.toml"),
            "id=\"yabai\"\nslot=\"tiling.wm\"\nstability=\"stable\"\nplatforms=[\"darwin\"]\ndefault=true\n");
        let komorebi = vdir.join("komorebi");
        fs.add_dir(&komorebi);
        fs.add_file(komorebi.join("variant.toml"),
            "id=\"komorebi\"\nslot=\"tiling.wm\"\nstability=\"experimental\"\nplatforms=[\"linux\"]\ndefault=false\n");
        let features_dir = PathBuf::from("/feats");
        fs.add_dir(&features_dir);
        fs.add_file(
            features_dir.join("tiling.toml"),
            "[meta]\ndescription=\"\"\n",
        );
        let engine = KaizenEngine::new(features_dir, Arc::clone(&fs) as Arc<dyn FileSystem>)
            .with_variants_dir(variants_dir);
        // With darwin OS (detected), komorebi should be filtered out
        // tiling.wm has only yabai (darwin) → choices=[yabai], slot present
        let features = engine.list_wizard_features(true).unwrap();
        let slot = features[0].slot.as_ref().expect("slot present");
        assert!(
            !slot.choices.iter().any(|c| c.id == "komorebi"),
            "linux-only filtered"
        );
    }

    #[test]
    fn bump_executes_in_category_order() {
        let cache_json = r#"{
            "alpha": {
                "category": "ai",
                "bump": {"run": [{"run": ["alpha-cmd"]}], "capture": []}
            },
            "beta": {
                "category": "dev",
                "bump": {"run": [{"run": ["beta-cmd"]}], "capture": []}
            },
            "gamma": {
                "category": "system",
                "bump": {"run": [{"run": ["gamma-cmd"]}], "capture": []}
            }
        }"#;
        let fs = Arc::new(MemFileSystem::new());
        let cache_path = PathBuf::from("/cache.json");
        fs.add_file(&cache_path, cache_json);
        let engine = KaizenEngine::cache_only(Arc::clone(&fs) as Arc<dyn FileSystem>)
            .with_nix_cache(cache_path);
        let config: UserConfig = toml::from_str(
            "schema_version=1\n[dotfiles]\nbackend=\"chezmoi\"\n\
             [features.alpha]\nenabled=true\n\
             [features.beta]\nenabled=true\n\
             [features.gamma]\nenabled=true\n",
        )
        .unwrap();
        let bumps = engine.bump_for_enabled_features(&config).unwrap();
        let names: Vec<&str> = bumps.iter().map(|(n, _)| n.as_str()).collect();
        assert_eq!(
            names,
            vec!["beta", "gamma", "alpha"],
            "expected dev → system → ai order"
        );
    }

    #[test]
    fn update_hooks_execute_in_category_order() {
        let cache_json = r#"{
            "alpha": {
                "category": "ai",
                "update": [{"run": ["alpha-update"]}]
            },
            "beta": {
                "category": "dev",
                "update": [{"run": ["beta-update"]}]
            },
            "gamma": {
                "category": "system",
                "update": [{"run": ["gamma-update"]}]
            }
        }"#;
        let fs = Arc::new(MemFileSystem::new());
        let cache_path = PathBuf::from("/cache.json");
        fs.add_file(&cache_path, cache_json);
        let engine = KaizenEngine::cache_only(Arc::clone(&fs) as Arc<dyn FileSystem>)
            .with_nix_cache(cache_path);
        let config: UserConfig = toml::from_str(
            "schema_version=1\n[dotfiles]\nbackend=\"chezmoi\"\n\
             [features.alpha]\nenabled=true\n\
             [features.beta]\nenabled=true\n\
             [features.gamma]\nenabled=true\n",
        )
        .unwrap();
        let hooks = engine.update_hooks_for_enabled_features(&config).unwrap();
        let cmds: Vec<&str> = hooks.iter().map(|h| h.run[0].as_str()).collect();
        assert_eq!(
            cmds,
            vec!["beta-update", "gamma-update", "alpha-update"],
            "expected dev → system → ai order"
        );
    }
}
