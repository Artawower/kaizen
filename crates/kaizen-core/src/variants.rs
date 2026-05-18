use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{FileSystem, KaizenError, TargetOs};

// ── Domain types ──────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Stability {
    Stable,
    Experimental,
}

impl Stability {
    pub fn as_str(&self) -> &'static str {
        match self {
            Stability::Stable => "stable",
            Stability::Experimental => "experimental",
        }
    }
}

impl std::fmt::Display for Stability {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Slot {
    pub id: String,
    #[serde(default)]
    pub required: bool,
    #[serde(default)]
    pub description: Option<String>,
}

/// Parsed from `features/<feature>/variants/<id>/variant.toml`.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct VariantManifest {
    pub id: String,
    /// Fully-qualified slot reference: `<feature>.<slot_id>`, e.g. `tiling.wm`.
    pub slot: String,
    #[serde(default)]
    pub title: Option<String>,
    pub stability: Stability,
    #[serde(default)]
    pub platforms: Vec<String>,
    #[serde(default)]
    pub default: bool,
    #[serde(default)]
    pub provides: VariantProvides,
    #[serde(default)]
    pub requires: VariantRequires,
    /// Absolute path to the variant's directory (populated by the loader, not
    /// present in the TOML file itself).
    #[serde(skip)]
    pub dir: PathBuf,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct VariantProvides {
    #[serde(default)]
    pub nix_modules: Vec<PathBuf>,
    #[serde(default)]
    pub dotfile_paths: Vec<PathBuf>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct VariantRequires {
    #[serde(default)]
    pub features: Vec<String>,
}

// ── Discovery ─────────────────────────────────────────────────────────────────

/// Discover all variants under `features_dir/<feature>/variants/*/variant.toml`.
pub fn discover_variants(
    features_dir: &Path,
    fs: &dyn FileSystem,
) -> Result<Vec<VariantManifest>, KaizenError> {
    if !fs.exists(features_dir) {
        return Ok(vec![]);
    }
    let mut out = Vec::new();
    let feature_entries = fs.read_dir_paths(features_dir).unwrap_or_default();
    for feature_dir in feature_entries {
        let variants_dir = feature_dir.join("variants");
        if !fs.exists(&variants_dir) {
            continue;
        }
        let variant_entries = fs.read_dir_paths(&variants_dir).unwrap_or_default();
        for variant_dir in variant_entries {
            let manifest_path = variant_dir.join("variant.toml");
            if !fs.exists(&manifest_path) {
                continue;
            }
            let raw = fs.read_to_string(&manifest_path)?;
            let mut manifest: VariantManifest =
                toml::from_str(&raw).map_err(|source| KaizenError::FeatureParse {
                    name: variant_dir
                        .file_name()
                        .and_then(|n| n.to_str())
                        .unwrap_or("?")
                        .to_owned(),
                    source,
                })?;
            manifest.dir = variant_dir;
            out.push(manifest);
        }
    }
    Ok(out)
}

// ── Resolver ──────────────────────────────────────────────────────────────────

pub struct VariantResolver {
    variants: Vec<VariantManifest>,
}

impl VariantResolver {
    pub fn new(variants: Vec<VariantManifest>) -> Self {
        Self { variants }
    }

    pub fn all(&self) -> &[VariantManifest] {
        &self.variants
    }

    /// Distinct slot fqns across all loaded variants.
    pub fn list_slots(&self) -> Vec<String> {
        let mut slots: Vec<String> = self
            .variants
            .iter()
            .map(|v| v.slot.clone())
            .collect::<std::collections::BTreeSet<_>>()
            .into_iter()
            .collect();
        slots.sort();
        slots
    }

    pub fn list_variants(&self, slot: &str) -> Vec<&VariantManifest> {
        self.variants.iter().filter(|v| v.slot == slot).collect()
    }

    pub fn filter_by_os<'a>(
        &'a self,
        os: &TargetOs,
        variants: Vec<&'a VariantManifest>,
    ) -> Vec<&'a VariantManifest> {
        let family = os.platform_family();
        variants
            .into_iter()
            .filter(|v| v.platforms.is_empty() || v.platforms.iter().any(|p| p == family))
            .collect()
    }

    pub fn filter_by_stability<'a>(
        &'a self,
        allow_experimental: bool,
        variants: Vec<&'a VariantManifest>,
    ) -> Vec<&'a VariantManifest> {
        if allow_experimental {
            return variants;
        }
        variants
            .into_iter()
            .filter(|v| v.stability == Stability::Stable)
            .collect()
    }

    /// Return the active variant id for `slot`:
    /// 1. Explicit selection in `variant_selections` (from data.toml `[variants]`).
    /// 2. Otherwise `None` — caller should use `default_for`.
    pub fn resolve_active<'a>(
        &'a self,
        slot: &str,
        variant_selections: &BTreeMap<String, String>,
    ) -> Option<&'a VariantManifest> {
        let selected_id = variant_selections.get(slot)?;
        self.variants
            .iter()
            .find(|v| v.slot == slot && &v.id == selected_id)
    }

    /// Default variant for a slot on a given OS: first `default = true` stable
    /// variant that supports `os`.
    pub fn default_for<'a>(&'a self, slot: &str, os: &TargetOs) -> Option<&'a VariantManifest> {
        let family = os.platform_family();
        self.variants.iter().find(|v| {
            v.slot == slot
                && v.default
                && v.stability == Stability::Stable
                && (v.platforms.is_empty() || v.platforms.iter().any(|p| p == family))
        })
    }

    /// Effective variant for a slot: explicit selection → default → None.
    pub fn effective<'a>(
        &'a self,
        slot: &str,
        os: &TargetOs,
        variant_selections: &BTreeMap<String, String>,
    ) -> Option<&'a VariantManifest> {
        self.resolve_active(slot, variant_selections)
            .or_else(|| self.default_for(slot, os))
    }

    /// Collect dotfile_paths owned by variants that are **inactive** for their
    /// slot.  These paths should be added to `.chezmoiignore` so that chezmoi
    /// does not deploy them.
    pub fn inactive_dotfile_paths(
        &self,
        os: &TargetOs,
        variant_selections: &BTreeMap<String, String>,
    ) -> Vec<PathBuf> {
        let mut paths = Vec::new();
        for slot in self.list_slots() {
            let active = self.effective(&slot, os, variant_selections);
            let active_id = active.map(|v| v.id.as_str());
            for variant in self.list_variants(&slot) {
                let eligible_os = variant.platforms.is_empty()
                    || variant.platforms.iter().any(|p| p == os.platform_family());
                if !eligible_os {
                    continue;
                }
                if Some(variant.id.as_str()) != active_id {
                    paths.extend(variant.provides.dotfile_paths.clone());
                }
            }
        }
        paths.sort();
        paths.dedup();
        paths
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn make_variant(
        id: &str,
        slot: &str,
        stability: Stability,
        platform: &str,
        default: bool,
    ) -> VariantManifest {
        VariantManifest {
            id: id.to_owned(),
            slot: slot.to_owned(),
            title: None,
            stability,
            platforms: vec![platform.to_owned()],
            default,
            provides: VariantProvides {
                nix_modules: vec![],
                dotfile_paths: vec![PathBuf::from(format!("dot_config/{id}/"))],
            },
            requires: VariantRequires::default(),
            dir: PathBuf::new(),
        }
    }

    fn resolver_with_tiling() -> VariantResolver {
        VariantResolver::new(vec![
            make_variant("yabai", "tiling.wm", Stability::Stable, "darwin", true),
            make_variant(
                "aerospace",
                "tiling.wm",
                Stability::Experimental,
                "darwin",
                false,
            ),
            make_variant(
                "komorebi",
                "tiling.wm",
                Stability::Experimental,
                "linux",
                false,
            ),
        ])
    }

    #[test]
    fn list_slots_returns_distinct_sorted() {
        let r = resolver_with_tiling();
        assert_eq!(r.list_slots(), vec!["tiling.wm"]);
    }

    #[test]
    fn list_variants_for_slot() {
        let r = resolver_with_tiling();
        let ids: Vec<_> = r
            .list_variants("tiling.wm")
            .iter()
            .map(|v| v.id.as_str())
            .collect();
        assert!(ids.contains(&"yabai"));
        assert!(ids.contains(&"aerospace"));
    }

    #[test]
    fn filter_by_os_excludes_wrong_platform() {
        let r = resolver_with_tiling();
        let all = r.list_variants("tiling.wm");
        let darwin = r.filter_by_os(&TargetOs::Darwin, all);
        let ids: Vec<_> = darwin.iter().map(|v| v.id.as_str()).collect();
        assert!(ids.contains(&"yabai"));
        assert!(ids.contains(&"aerospace"));
        assert!(!ids.contains(&"komorebi"));
    }

    #[test]
    fn filter_by_stability_excludes_experimental() {
        let r = resolver_with_tiling();
        let all = r.list_variants("tiling.wm");
        let stable = r.filter_by_stability(false, all);
        assert_eq!(stable.len(), 1);
        assert_eq!(stable[0].id, "yabai");
    }

    #[test]
    fn default_for_returns_stable_default_for_os() {
        let r = resolver_with_tiling();
        let d = r.default_for("tiling.wm", &TargetOs::Darwin).unwrap();
        assert_eq!(d.id, "yabai");
    }

    #[test]
    fn default_for_returns_none_for_wrong_os() {
        let r = VariantResolver::new(vec![make_variant(
            "yabai",
            "tiling.wm",
            Stability::Stable,
            "darwin",
            true,
        )]);
        assert!(r.default_for("tiling.wm", &TargetOs::Fedora).is_none());
    }

    #[test]
    fn resolve_active_reads_from_selections() {
        let r = resolver_with_tiling();
        let mut sel = BTreeMap::new();
        sel.insert("tiling.wm".to_owned(), "aerospace".to_owned());
        let active = r.resolve_active("tiling.wm", &sel).unwrap();
        assert_eq!(active.id, "aerospace");
    }

    #[test]
    fn effective_falls_back_to_default_when_no_selection() {
        let r = resolver_with_tiling();
        let active = r
            .effective("tiling.wm", &TargetOs::Darwin, &BTreeMap::new())
            .unwrap();
        assert_eq!(active.id, "yabai");
    }

    #[test]
    fn inactive_dotfile_paths_excludes_active_variant() {
        let r = resolver_with_tiling();
        let mut sel = BTreeMap::new();
        sel.insert("tiling.wm".to_owned(), "aerospace".to_owned());
        let inactive = r.inactive_dotfile_paths(&TargetOs::Darwin, &sel);
        assert!(inactive
            .iter()
            .any(|p| p == &PathBuf::from("dot_config/yabai/")));
        assert!(!inactive
            .iter()
            .any(|p| p == &PathBuf::from("dot_config/aerospace/")));
    }

    #[test]
    fn inactive_dotfile_paths_uses_default_when_no_selection() {
        let r = resolver_with_tiling();
        let inactive = r.inactive_dotfile_paths(&TargetOs::Darwin, &BTreeMap::new());
        assert!(!inactive
            .iter()
            .any(|p| p == &PathBuf::from("dot_config/yabai/")));
        assert!(inactive
            .iter()
            .any(|p| p == &PathBuf::from("dot_config/aerospace/")));
    }
}
