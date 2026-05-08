use std::path::{Path, PathBuf};
use std::process::Command;

use indexmap::IndexMap;
use serde::Serialize;

use crate::{ConfigPlan, KaizenError};

#[derive(Serialize)]
struct ChezmoidataFile<'a> {
    layout: &'a str,
    features: &'a IndexMap<String, bool>,
}

/// Generate chezmoidata content from scratch (used in tests and first-time setup).
pub fn generate_chezmoidata(plan: &ConfigPlan) -> Result<String, KaizenError> {
    let layout = plan.settings.layout.as_deref().unwrap_or("qwerty");
    let data = ChezmoidataFile {
        layout,
        features: &plan.features_data,
    };
    Ok(toml::to_string_pretty(&data)?)
}

/// Merge kaizen-managed keys (layout, features) into an existing chezmoidata file.
///
/// Preserves all other keys (username, hostname, email, models, etc.) that
/// are maintained outside of kaizen. If the file does not exist, behaves
/// identically to `generate_chezmoidata`.
pub fn merge_chezmoidata(existing_path: &Path, plan: &ConfigPlan) -> Result<String, KaizenError> {
    let layout = plan.settings.layout.as_deref().unwrap_or("qwerty");

    let mut table: toml::map::Map<String, toml::Value> = if existing_path.exists() {
        let raw = std::fs::read_to_string(existing_path)?;
        match toml::from_str::<toml::Value>(&raw) {
            Ok(toml::Value::Table(t)) => t,
            _ => toml::map::Map::new(),
        }
    } else {
        toml::map::Map::new()
    };

    table.insert("layout".to_owned(), toml::Value::String(layout.to_owned()));

    // Start with existing feature values so unknown features (e.g. "vcs") are
    // preserved. Kaizen-managed features are then overlaid on top.
    let mut features: toml::map::Map<String, toml::Value> = table
        .get("features")
        .and_then(|v| v.as_table())
        .cloned()
        .unwrap_or_default();
    for (k, v) in &plan.features_data {
        features.insert(k.clone(), toml::Value::Boolean(*v));
    }
    table.insert("features".to_owned(), toml::Value::Table(features));

    Ok(toml::to_string_pretty(&toml::Value::Table(table))?)
}

pub fn current_remote(source_dir: &Path) -> Result<Option<String>, KaizenError> {
    let out = Command::new("git")
        .arg("-C")
        .arg(source_dir)
        .args(["remote", "get-url", "origin"])
        .output()?;
    if !out.status.success() {
        return Ok(None);
    }
    Ok(Some(String::from_utf8_lossy(&out.stdout).trim().to_owned()))
}

pub fn backup_source_dir(source_dir: &Path) -> Result<PathBuf, KaizenError> {
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let name = source_dir.file_name().unwrap_or_default().to_string_lossy();
    let backup = source_dir.with_file_name(format!("{name}.bak.{ts}"));
    std::fs::rename(source_dir, &backup)?;
    Ok(backup)
}

#[derive(Debug, Clone)]
pub enum SourcePathState {
    /// `chezmoi source-path` returned a valid path — chezmoi is initialized.
    Confirmed(PathBuf),
    /// `chezmoi source-path` ran but reported no source dir — chezmoi is not initialized.
    /// Carries the conventional default path where init would place the source.
    Uninitialized(PathBuf),
}

impl SourcePathState {
    pub fn path(&self) -> &Path {
        match self {
            SourcePathState::Confirmed(p) | SourcePathState::Uninitialized(p) => p,
        }
    }

    pub fn into_confirmed(self) -> Result<PathBuf, KaizenError> {
        match self {
            SourcePathState::Confirmed(p) => Ok(p),
            SourcePathState::Uninitialized(_) => Err(KaizenError::ChezmoidataTargetUnknown),
        }
    }
}

pub fn standalone_source_dir() -> Result<Option<PathBuf>, KaizenError> {
    let out = Command::new("chezmoi").arg("source-path").output()?;
    if !out.status.success() {
        return Ok(None);
    }
    let path_str = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if path_str.is_empty() {
        return Ok(None);
    }
    let path = PathBuf::from(path_str);
    if path.exists() {
        Ok(Some(path))
    } else {
        Ok(None)
    }
}

pub fn init_source(url: &str) -> Result<(), KaizenError> {
    let status = Command::new("chezmoi").args(["init", url]).status()?;
    if !status.success() {
        return Err(KaizenError::ChezmoidataInitFailed {
            url: url.to_owned(),
            code: status.code(),
        });
    }
    Ok(())
}

pub fn remotes_match(a: &str, b: &str) -> bool {
    normalize_remote(a) == normalize_remote(b)
}

fn normalize_remote(url: &str) -> String {
    let url = url.trim();
    let without_scheme = if let Some(rest) = url.strip_prefix("git@") {
        rest.replacen(':', "/", 1)
    } else if let Some(rest) = url.strip_prefix("https://") {
        rest.to_owned()
    } else if let Some(rest) = url.strip_prefix("http://") {
        rest.to_owned()
    } else {
        url.to_owned()
    };
    without_scheme
        .trim_end_matches(".git")
        .trim_end_matches('/')
        .to_lowercase()
}

pub fn source_path(plan: &ConfigPlan) -> Result<SourcePathState, KaizenError> {
    if plan.backend != "chezmoi" {
        return Err(KaizenError::UnsupportedDotfilesBackend {
            backend: plan.backend.clone(),
        });
    }

    let out = Command::new("chezmoi").arg("source-path").output()?;

    if out.status.success() {
        let path = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if !path.is_empty() {
            let path = PathBuf::from(path);
            if path.exists() {
                return Ok(SourcePathState::Confirmed(path));
            }
            return Ok(SourcePathState::Uninitialized(path));
        }
    }

    let fallback = dirs::home_dir()
        .map(|h| h.join(".local/share/chezmoi"))
        .ok_or(KaizenError::ChezmoidataTargetUnknown)?;

    Ok(SourcePathState::Uninitialized(fallback))
}

#[cfg(test)]
mod tests {
    use indexmap::IndexMap;

    use crate::{ConfigPlan, UserSettings};

    use super::{generate_chezmoidata, merge_chezmoidata};

    fn make_plan(features: &[(&str, bool)], layout: Option<&str>) -> ConfigPlan {
        ConfigPlan {
            backend: "chezmoi".to_owned(),
            dotfiles_source: None,
            features_data: features.iter().map(|(k, v)| (k.to_string(), *v)).collect(),
            settings: UserSettings {
                layout: layout.map(str::to_owned),
            },
        }
    }

    #[test]
    fn generates_features_and_layout() {
        let plan = make_plan(&[("core", true), ("emacs", false)], Some("colemak"));
        let toml = generate_chezmoidata(&plan).unwrap();
        assert!(toml.contains("core = true"));
        assert!(toml.contains("emacs = false"));
        assert!(toml.contains("layout = \"colemak\""));
    }

    #[test]
    fn defaults_layout_to_qwerty_when_unset() {
        let plan = make_plan(&[], None);
        let toml = generate_chezmoidata(&plan).unwrap();
        assert!(toml.contains("layout = \"qwerty\""));
    }

    #[test]
    fn empty_features_produces_valid_toml() {
        let plan = make_plan(&[], Some("colemak"));
        let toml = generate_chezmoidata(&plan).unwrap();
        assert!(!toml.is_empty());
        let _: toml::Value = toml::from_str(&toml).expect("must be valid toml");
    }

    #[test]
    fn merge_preserves_unknown_keys() {
        let existing = "username = \"alice\"\nhostname = \"macbook\"\n\n[models]\ndefault = \"gpt-4\"\n\n[features]\ncore = true\n";
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(".chezmoidata.toml");
        std::fs::write(&path, existing).unwrap();

        let plan = make_plan(&[("frontend", true)], Some("qwerty"));
        let merged = merge_chezmoidata(&path, &plan).unwrap();

        assert!(merged.contains("username = \"alice\""), "must preserve username");
        assert!(merged.contains("hostname = \"macbook\""), "must preserve hostname");
        assert!(merged.contains("default = \"gpt-4\""), "must preserve models");
        assert!(merged.contains("frontend = true"), "must update features");
        assert!(merged.contains("layout = \"qwerty\""), "must update layout");
    }

    #[test]
    fn merge_preserves_unknown_feature_keys() {
        let existing = "layout = \"colemak\"\n\n[features]\ncore = true\nvcs = true\n";
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(".chezmoidata.toml");
        std::fs::write(&path, existing).unwrap();

        // kaizen config does not know about 'vcs'
        let plan = make_plan(&[("core", true), ("frontend", false)], Some("colemak"));
        let merged = merge_chezmoidata(&path, &plan).unwrap();

        assert!(
            merged.contains("vcs = true"),
            "unknown feature 'vcs' must be preserved: {merged}"
        );
        assert!(merged.contains("frontend = false"), "kaizen-managed feature must be updated");
    }

    #[test]
    fn merge_updates_layout_without_touching_rest() {
        let existing = "layout = \"colemak\"\nusername = \"bob\"\n\n[features]\ncore = true\n";
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(".chezmoidata.toml");
        std::fs::write(&path, existing).unwrap();

        let plan = make_plan(&[("core", true)], Some("qwerty"));
        let merged = merge_chezmoidata(&path, &plan).unwrap();

        assert!(
            merged.contains("layout = \"qwerty\""),
            "layout must be updated"
        );
        assert!(
            merged.contains("username = \"bob\""),
            "username must be preserved"
        );
    }

    #[test]
    fn merge_on_nonexistent_file_equals_generate() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("nonexistent.toml");

        let plan = make_plan(&[("core", true)], Some("colemak"));
        let merged = merge_chezmoidata(&path, &plan).unwrap();
        let generated = generate_chezmoidata(&plan).unwrap();

        let merged_val: toml::Value = toml::from_str(&merged).unwrap();
        let gen_val: toml::Value = toml::from_str(&generated).unwrap();
        assert_eq!(merged_val, gen_val);
    }

    #[test]
    fn rejects_non_chezmoi_backend() {
        let plan = ConfigPlan {
            backend: "nix".to_owned(),
            dotfiles_source: None,
            features_data: IndexMap::new(),
            settings: UserSettings { layout: None },
        };
        assert!(super::source_path(&plan).is_err());
    }
}
