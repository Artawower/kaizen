use crate::{config::ExtraConfig, CURRENT_SCHEMA_VERSION};

/// Render a kaizen `config.toml` from selected features, layout, and dotfiles source.
/// `extra` is preserved verbatim — the wizard never modifies user-managed packages.
///
/// Returns valid TOML content ready to be written to disk.
pub fn render_config(
    all_features: &[(String, Option<String>)],
    selected: &[String],
    layout: &str,
    dotfiles_source: &str,
    extra: &ExtraConfig,
) -> String {
    let mut out = String::new();
    out.push_str(&format!("schema_version = {CURRENT_SCHEMA_VERSION}\n\n"));
    for (name, _) in all_features {
        let enabled = selected.contains(name);
        out.push_str(&format!("[features.{name}]\nenabled = {enabled}\n\n"));
    }
    out.push_str(&format!("[settings]\nlayout = {}\n\n", toml_string(layout)));
    out.push_str("[dotfiles]\nbackend = \"chezmoi\"\n");
    out.push_str(&format!("source = {}\n", toml_string(dotfiles_source)));
    if !extra.is_empty() {
        out.push_str("\n[extra]\n");
        if !extra.nix_packages.is_empty() {
            out.push_str(&format!(
                "nix_packages = {}\n",
                toml_list(&extra.nix_packages)
            ));
        }
        if !extra.brew_casks.is_empty() {
            out.push_str(&format!("brew_casks = {}\n", toml_list(&extra.brew_casks)));
        }
        if !extra.brew_formulas.is_empty() {
            out.push_str(&format!(
                "brew_formulas = {}\n",
                toml_list(&extra.brew_formulas)
            ));
        }
        if !extra.brew_taps.is_empty() {
            out.push_str(&format!("brew_taps = {}\n", toml_list(&extra.brew_taps)));
        }
    }
    out
}

fn toml_list(items: &[String]) -> String {
    let quoted: Vec<_> = items.iter().map(|s| toml_string(s)).collect();
    format!("[{}]", quoted.join(", "))
}

fn toml_string(s: &str) -> String {
    toml::Value::String(s.to_owned()).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn features(names: &[&str]) -> Vec<(String, Option<String>)> {
        names.iter().map(|n| (n.to_string(), None)).collect()
    }

    fn empty_extra() -> ExtraConfig {
        ExtraConfig::default()
    }

    #[test]
    fn render_includes_schema_version() {
        let out = render_config(&[], &[], "qwerty", "https://example.com", &empty_extra());
        assert!(out.contains(&format!("schema_version = {CURRENT_SCHEMA_VERSION}")));
    }

    #[test]
    fn render_marks_selected_features_enabled() {
        let all = features(&["git", "rust"]);
        let out = render_config(
            &all,
            &["git".into()],
            "qwerty",
            "https://example.com",
            &empty_extra(),
        );
        assert!(out.contains("[features.git]\nenabled = true"));
        assert!(out.contains("[features.rust]\nenabled = false"));
    }

    #[test]
    fn render_includes_layout() {
        let out = render_config(&[], &[], "colemak", "https://example.com", &empty_extra());
        assert!(out.contains("layout = \"colemak\""));
    }

    #[test]
    fn render_includes_dotfiles_source() {
        let out = render_config(
            &[],
            &[],
            "qwerty",
            "https://github.com/user/dots",
            &empty_extra(),
        );
        assert!(out.contains("source = \"https://github.com/user/dots\""));
    }

    #[test]
    fn render_dotfiles_section_has_chezmoi_backend() {
        let out = render_config(&[], &[], "qwerty", "https://example.com", &empty_extra());
        assert!(out.contains("[dotfiles]\nbackend = \"chezmoi\""));
    }

    #[test]
    fn render_preserves_extra_nix_packages() {
        let extra = ExtraConfig {
            nix_packages: vec!["ripgrep".into(), "fd".into()],
            ..Default::default()
        };
        let out = render_config(&[], &[], "qwerty", "https://example.com", &extra);
        assert!(out.contains("[extra]"));
        assert!(out.contains("nix_packages = [\"ripgrep\", \"fd\"]"));
    }

    #[test]
    fn render_skips_extra_section_when_empty() {
        let out = render_config(&[], &[], "qwerty", "https://example.com", &empty_extra());
        assert!(!out.contains("[extra]"));
    }
}
