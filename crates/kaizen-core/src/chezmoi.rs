use std::path::{Path, PathBuf};
use std::process::Command;

use indexmap::IndexMap;
use serde::Serialize;

use crate::{ConfigPlan, KaizenError};

#[derive(Serialize)]
struct ChezmoidataFile<'a> {
    features: &'a IndexMap<String, bool>,
    settings: ChezmoidataSettings<'a>,
}

#[derive(Serialize)]
struct ChezmoidataSettings<'a> {
    layout: &'a str,
}

pub fn generate_chezmoidata(plan: &ConfigPlan) -> Result<String, KaizenError> {
    let layout = plan.settings.layout.as_deref().unwrap_or("qwerty");
    let data = ChezmoidataFile {
        features: &plan.features_data,
        settings: ChezmoidataSettings { layout },
    };
    Ok(toml::to_string_pretty(&data)?)
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

    use super::generate_chezmoidata;

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
