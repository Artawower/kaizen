use indexmap::IndexMap;

use crate::{
    feature::ProgramSection, ConfigPlan, FeatureStore, HookPlan, InstallPlan, KaizenError,
    TargetOs, UserConfig, WorkflowPlan,
};

pub fn build_plan(
    config: &UserConfig,
    store: &FeatureStore,
    target_os: TargetOs,
) -> Result<WorkflowPlan, KaizenError> {
    let mut programs: IndexMap<String, String> = IndexMap::new();
    let mut dev_tools: IndexMap<String, String> = IndexMap::new();
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

    Ok(WorkflowPlan::new(
        target_os,
        selected_features,
        InstallPlan {
            programs: programs.into_values().collect(),
            dev_tools,
        },
        build_config_plan(config),
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
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;
    use crate::feature::ProgramSection;

    fn fixture_path(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name)
    }

    fn fixture_config(name: &str) -> UserConfig {
        crate::config::load(&fixture_path(name)).unwrap()
    }

    fn fixture_store() -> FeatureStore {
        FeatureStore::new(fixture_path("features"))
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
        let plan = build_plan(&config, &fixture_store(), TargetOs::Darwin).unwrap();
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
        let plan = build_plan(&config, &fixture_store(), TargetOs::Darwin).unwrap();
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
