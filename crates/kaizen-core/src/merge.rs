use indexmap::IndexMap;

use crate::{
    feature::ProgramSection, ConfigPlan, FeatureStore, HookPlan, InstallPlan, KaizenError,
    TargetOs, UserConfig, WorkflowPlan,
};

pub fn build_plan(
    config: &UserConfig,
    store: &FeatureStore,
    all_feature_names: &[String],
    target_os: TargetOs,
) -> Result<WorkflowPlan, KaizenError> {
    let mut programs: IndexMap<String, String> = IndexMap::new();
    let mut dev_tools: IndexMap<String, String> = IndexMap::new();
    let mut brew_source_formulas: Vec<String> = Vec::new();
    let mut warnings: Vec<String> = Vec::new();
    let mut selected_features: Vec<String> = Vec::new();
    let mut hook_plan = HookPlan::default();

    for (feature_name, selection) in &config.features {
        if !selection.enabled {
            continue;
        }

        let Some(feature) = store.load_optional(feature_name)? else {
            warnings.push(format!(
                "feature '{feature_name}' not found in features dir"
            ));
            continue;
        };

        selected_features.push(feature_name.clone());

        hook_plan
            .post_install
            .extend(feature.hooks.post_install.iter().cloned());
        hook_plan
            .post_apply
            .extend(feature.hooks.post_apply.iter().cloned());
        hook_plan
            .post_update
            .extend(feature.hooks.post_update.iter().cloned());

        if let Some(ref prog) = feature.programs {
            merge_programs(&mut programs, prog, &target_os);
        }
        if let Some(ref mise) = feature.mise {
            merge_mise(&mut dev_tools, &mise.tools, feature_name, &mut warnings);
        }

        for os_key in target_os.section_keys() {
            if let Some(os_section) = feature.os.get(os_key) {
                if let Some(ref prog) = os_section.programs {
                    merge_programs(&mut programs, prog, &target_os);
                }
                if let Some(ref mise) = os_section.mise {
                    merge_mise(&mut dev_tools, &mise.tools, feature_name, &mut warnings);
                }
                for formula in &os_section.brew_source_formulas {
                    if !brew_source_formulas.contains(formula) {
                        brew_source_formulas.push(formula.clone());
                    }
                }
            }
        }

        for (atom_name, atom) in &feature.atoms {
            if selection.disabled_atoms.contains(atom_name) {
                continue;
            }
            if let Some(ref prog) = atom.programs {
                merge_programs(&mut programs, prog, &target_os);
            }
            if let Some(ref mise) = atom.mise {
                merge_mise(&mut dev_tools, &mise.tools, feature_name, &mut warnings);
            }
        }
    }

    let mut config_plan = build_config_plan(config);
    // Ensure every known feature is present in the data snapshot, even when
    // not selected. Templates and Nix configs rely on a complete map.
    // Source of truth: manifest (via all_feature_names), or store as fallback.
    for name in all_feature_names {
        config_plan
            .features_data
            .entry(name.clone())
            .or_insert(false);
    }

    Ok(WorkflowPlan::new(
        target_os,
        selected_features,
        InstallPlan {
            programs: programs.into_values().collect(),
            dev_tools,
            brew_source_formulas,
        },
        config_plan,
        hook_plan,
        warnings,
    ))
}

fn resolve_program(canonical: &str, section: &ProgramSection, target_os: &TargetOs) -> String {
    target_os
        .section_keys()
        .into_iter()
        .rev()
        .find_map(|key| {
            section
                .overrides
                .get(key)
                .and_then(|map| map.get(canonical))
                .cloned()
        })
        .unwrap_or_else(|| canonical.to_owned())
}

fn merge_programs(
    out: &mut IndexMap<String, String>,
    section: &ProgramSection,
    target_os: &TargetOs,
) {
    for canonical in &section.packages {
        let resolved = resolve_program(canonical, section, target_os);
        out.insert(canonical.clone(), resolved);
    }
}

fn merge_mise(
    out: &mut IndexMap<String, String>,
    tools: &IndexMap<String, String>,
    feature_name: &str,
    warnings: &mut Vec<String>,
) {
    for (name, version) in tools {
        if let Some(existing) = out.get(name.as_str()) {
            if existing != version {
                warnings.push(format!(
                    "mise tool '{name}' conflict in '{feature_name}': \
                     '{existing}' vs '{version}' — keeping '{existing}'"
                ));
            }
            continue;
        }
        out.insert(name.clone(), version.clone());
    }
}

fn build_config_plan(config: &UserConfig) -> ConfigPlan {
    ConfigPlan {
        backend: config
            .dotfiles
            .backend
            .clone()
            .unwrap_or_else(|| "chezmoi".to_owned()),
        dotfiles_source: config.dotfiles.source.clone(),
        features_data: config
            .features
            .iter()
            .map(|(k, v)| (k.clone(), v.enabled))
            .collect(),
        settings: config.settings.clone(),
        extra: config.extra.clone(),
        variants: config.variants.clone(),
    }
}

#[cfg(test)]
mod tests {
    use std::path::{Path, PathBuf};
    use std::sync::Arc;

    use super::*;
    use crate::{feature::ProgramSection, FileSystem, KaizenError};

    struct DiskFileSystem;

    impl FileSystem for DiskFileSystem {
        fn read_to_string(&self, path: &Path) -> Result<String, KaizenError> {
            std::fs::read_to_string(path).map_err(KaizenError::Io)
        }

        fn read_dir_paths(&self, path: &Path) -> Result<Vec<PathBuf>, KaizenError> {
            let entries = std::fs::read_dir(path).map_err(KaizenError::Io)?;
            entries
                .map(|e| e.map(|e| e.path()).map_err(KaizenError::Io))
                .collect()
        }

        fn exists(&self, path: &Path) -> bool {
            path.exists()
        }

        fn is_dir(&self, path: &Path) -> bool {
            path.is_dir()
        }

        fn write(&self, path: &Path, content: &[u8]) -> Result<(), KaizenError> {
            std::fs::write(path, content).map_err(KaizenError::Io)
        }

        fn create_dir_all(&self, path: &Path) -> Result<(), KaizenError> {
            std::fs::create_dir_all(path).map_err(KaizenError::Io)
        }

        fn rename(&self, from: &Path, to: &Path) -> Result<(), KaizenError> {
            std::fs::rename(from, to).map_err(KaizenError::Io)
        }

        fn remove_file(&self, path: &Path) -> Result<(), KaizenError> {
            std::fs::remove_file(path).map_err(KaizenError::Io)
        }

        fn remove_dir_all(&self, path: &Path) -> Result<(), KaizenError> {
            std::fs::remove_dir_all(path).map_err(KaizenError::Io)
        }
    }

    fn fixture_path(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name)
    }

    fn fixture_config(name: &str) -> UserConfig {
        crate::config::load_with(&fixture_path(name), &DiskFileSystem).unwrap()
    }

    fn fixture_store() -> FeatureStore {
        FeatureStore::new(fixture_path("features"), Arc::new(DiskFileSystem))
    }

    fn prog(pkgs: &[&str]) -> ProgramSection {
        ProgramSection {
            packages: pkgs.iter().map(|s| s.to_string()).collect(),
            overrides: IndexMap::new(),
        }
    }

    #[test]
    fn deduplicates_programs() {
        let mut out = IndexMap::new();
        merge_programs(&mut out, &prog(&["ripgrep", "fd"]), &TargetOs::Darwin);
        merge_programs(&mut out, &prog(&["ripgrep", "emacs"]), &TargetOs::Darwin);
        assert_eq!(
            out.values().collect::<Vec<_>>(),
            vec!["ripgrep", "fd", "emacs"]
        );
    }

    #[test]
    fn applies_fedora_override() {
        let mut out = IndexMap::new();
        let mut overrides: IndexMap<String, IndexMap<String, String>> = IndexMap::new();
        overrides
            .entry("fedora".to_owned())
            .or_default()
            .insert("fd".to_owned(), "fd-find".to_owned());
        let sec = ProgramSection {
            packages: vec!["fd".to_owned()],
            overrides,
        };
        merge_programs(&mut out, &sec, &TargetOs::Fedora);
        assert_eq!(out["fd"], "fd-find");
    }

    #[test]
    fn later_os_section_overrides_base() {
        let mut out = IndexMap::new();
        merge_programs(&mut out, &prog(&["fd"]), &TargetOs::Fedora);
        assert_eq!(out["fd"], "fd");

        let mut overrides: IndexMap<String, IndexMap<String, String>> = IndexMap::new();
        overrides
            .entry("fedora".to_owned())
            .or_default()
            .insert("fd".to_owned(), "fd-find".to_owned());
        let sec = ProgramSection {
            packages: vec!["fd".to_owned()],
            overrides,
        };
        merge_programs(&mut out, &sec, &TargetOs::Fedora);
        assert_eq!(out["fd"], "fd-find");
    }

    #[test]
    fn hooks_collected_from_enabled_features() {
        let config = fixture_config("config-hooks.toml");
        let plan = build_plan(
            &config,
            &fixture_store(),
            &fixture_store().list().unwrap(),
            TargetOs::Darwin,
        )
        .unwrap();
        assert!(plan
            .hook_plan
            .post_install
            .contains(&"echo alpha-post-install".to_owned()));
        assert!(plan
            .hook_plan
            .post_install
            .contains(&"echo beta-post-install".to_owned()));
        assert!(plan
            .hook_plan
            .post_apply
            .contains(&"echo alpha-post-apply".to_owned()));
        assert!(plan
            .hook_plan
            .post_update
            .contains(&"echo beta-post-update".to_owned()));
    }

    #[test]
    fn hooks_not_collected_from_disabled_features() {
        let config = fixture_config("config-hooks-disabled.toml");
        let plan = build_plan(
            &config,
            &fixture_store(),
            &fixture_store().list().unwrap(),
            TargetOs::Darwin,
        )
        .unwrap();
        assert!(plan
            .hook_plan
            .post_install
            .contains(&"echo alpha-post-install".to_owned()));
        assert!(!plan
            .hook_plan
            .post_install
            .contains(&"echo beta-post-install".to_owned()));
        assert!(!plan
            .hook_plan
            .post_apply
            .contains(&"echo beta-post-apply".to_owned()));
        assert!(plan.hook_plan.post_update.is_empty());
    }

    #[test]
    fn all_store_features_present_in_data_even_when_not_selected() {
        // config-alpha-only.toml enables only `alpha`; store also has `beta`.
        // Both must appear in features_data: alpha=true, beta=false.
        let config = fixture_config("config-alpha-only.toml");
        let plan = build_plan(
            &config,
            &fixture_store(),
            &fixture_store().list().unwrap(),
            TargetOs::Darwin,
        )
        .unwrap();
        assert_eq!(plan.config_plan.features_data.get("alpha"), Some(&true));
        assert_eq!(plan.config_plan.features_data.get("beta"), Some(&false));
    }

    #[test]
    fn mise_conflict_keeps_first() {
        let mut out = IndexMap::new();
        let mut w = Vec::new();
        let a: IndexMap<_, _> = [("node".to_owned(), "lts".to_owned())].into();
        let b: IndexMap<_, _> = [("node".to_owned(), "22".to_owned())].into();
        merge_mise(&mut out, &a, "feat-a", &mut w);
        merge_mise(&mut out, &b, "feat-b", &mut w);
        assert_eq!(out["node"], "lts");
        assert!(!w.is_empty());
    }
}
