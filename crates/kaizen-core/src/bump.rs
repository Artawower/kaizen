use serde::Deserialize;

pub const BUMP_MANIFEST_FILE: &str = "bump.toml";

#[derive(Debug, Clone, Deserialize, Default)]
pub struct BumpManifest {
    #[serde(default)]
    pub steps: Vec<BumpStep>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct BumpStep {
    pub name: String,
    /// Command to run, e.g. `["mise", "upgrade", "--bump"]`.
    pub run: Vec<String>,
    /// Paths to `chezmoi re-add` after the command completes.
    /// `~` is expanded to the home directory.
    pub capture: Vec<String>,
}

impl BumpManifest {
    pub fn from_toml(content: &str) -> Result<Self, toml::de::Error> {
        toml::from_str(content)
    }

    /// Return steps matching `filter`.  Empty filter means all steps.
    pub fn filter_steps<'a>(&'a self, filter: &[String]) -> Vec<&'a BumpStep> {
        if filter.is_empty() {
            return self.steps.iter().collect();
        }
        self.steps
            .iter()
            .filter(|s| filter.contains(&s.name))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"
[[steps]]
name    = "mise"
run     = ["mise", "upgrade", "--bump"]
capture = ["~/.config/mise.lock"]

[[steps]]
name    = "nix"
run     = ["nix", "flake", "update"]
capture = ["~/.config/nix/flake.lock"]
"#;

    #[test]
    fn parses_steps() {
        let m = BumpManifest::from_toml(SAMPLE).unwrap();
        assert_eq!(m.steps.len(), 2);
        assert_eq!(m.steps[0].name, "mise");
        assert_eq!(m.steps[1].name, "nix");
    }

    #[test]
    fn filter_empty_returns_all() {
        let m = BumpManifest::from_toml(SAMPLE).unwrap();
        assert_eq!(m.filter_steps(&[]).len(), 2);
    }

    #[test]
    fn filter_by_name() {
        let m = BumpManifest::from_toml(SAMPLE).unwrap();
        let steps = m.filter_steps(&["nix".to_string()]);
        assert_eq!(steps.len(), 1);
        assert_eq!(steps[0].name, "nix");
    }

    #[test]
    fn filter_unknown_returns_empty() {
        let m = BumpManifest::from_toml(SAMPLE).unwrap();
        assert_eq!(m.filter_steps(&["unknown".to_string()]).len(), 0);
    }
}
