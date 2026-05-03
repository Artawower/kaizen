use std::path::PathBuf;
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

pub fn source_path(plan: &ConfigPlan) -> Result<(PathBuf, bool), KaizenError> {
    if plan.backend != "chezmoi" {
        return Err(KaizenError::UnsupportedDotfilesBackend {
            backend: plan.backend.clone(),
        });
    }

    let output = Command::new("chezmoi").arg("source-path").output();
    if let Ok(out) = output {
        if out.status.success() {
            let path = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !path.is_empty() {
                return Ok((PathBuf::from(path), false));
            }
        }
    }

    let fallback = dirs::home_dir()
        .map(|h| h.join(".local/share/chezmoi"))
        .ok_or(KaizenError::ChezmoidataTargetUnknown)?;

    Ok((fallback, true))
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
