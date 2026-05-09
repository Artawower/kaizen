use crate::CURRENT_SCHEMA_VERSION;

/// Render a kaizen `config.toml` from selected features, layout, and dotfiles source.
///
/// Returns valid TOML content ready to be written to disk.
pub fn render_config(
    all_features: &[(String, Option<String>)],
    selected: &[String],
    layout: &str,
    dotfiles_source: &str,
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
    out
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

    #[test]
    fn render_includes_schema_version() {
        let out = render_config(&[], &[], "qwerty", "https://example.com");
        assert!(out.contains(&format!("schema_version = {CURRENT_SCHEMA_VERSION}")));
    }

    #[test]
    fn render_marks_selected_features_enabled() {
        let all = features(&["git", "rust"]);
        let out = render_config(&all, &["git".into()], "qwerty", "https://example.com");
        assert!(out.contains("[features.git]\nenabled = true"));
        assert!(out.contains("[features.rust]\nenabled = false"));
    }

    #[test]
    fn render_includes_layout() {
        let out = render_config(&[], &[], "colemak", "https://example.com");
        assert!(out.contains("layout = \"colemak\""));
    }

    #[test]
    fn render_includes_dotfiles_source() {
        let out = render_config(&[], &[], "qwerty", "https://github.com/user/dots");
        assert!(out.contains("source = \"https://github.com/user/dots\""));
    }

    #[test]
    fn render_dotfiles_section_has_chezmoi_backend() {
        let out = render_config(&[], &[], "qwerty", "https://example.com");
        assert!(out.contains("[dotfiles]\nbackend = \"chezmoi\""));
    }
}
