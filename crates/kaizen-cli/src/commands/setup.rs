use std::path::Path;

use anyhow::Result;
use dialoguer::{theme::ColorfulTheme, Confirm, Input, Select};
use kaizen_core::{KaizenEngine, UserConfig};
use owo_colors::OwoColorize;

use crate::{output, selector};

pub fn run(engine: &KaizenEngine, config_path: &Path) -> Result<()> {
    output::page_header("setup");

    let existing = config_path
        .exists()
        .then(|| engine.load_config(config_path).ok())
        .flatten();

    let features = engine.list_features_with_meta()?;
    let Some(selected) = pick_features(&features, existing.as_ref())? else {
        return Ok(());
    };
    let layout = pick_layout(existing.as_ref())?;
    let dotfiles_source = pick_dotfiles_source(existing.as_ref())?;

    let toml = render_config(&features, &selected, &layout, dotfiles_source.as_deref());
    if write_config(config_path, &toml)? {
        print_next_steps(config_path);
    }
    Ok(())
}

fn pick_features(
    features: &[(String, Option<String>)],
    existing: Option<&UserConfig>,
) -> Result<Option<Vec<String>>> {
    let items = features
        .iter()
        .map(|(name, desc)| {
            let selected = existing
                .map(|c| c.features.get(name.as_str()).is_none_or(|f| f.enabled))
                .unwrap_or(true);
            selector::Item {
                name: name.clone(),
                desc: desc.clone(),
                selected,
            }
        })
        .collect();
    selector::multi_select("Select features", items)
}

fn pick_layout(existing: Option<&UserConfig>) -> Result<String> {
    let layouts = &["colemak", "qwerty"];
    let default_idx = existing
        .and_then(|c| c.settings.layout.as_deref())
        .and_then(|l| layouts.iter().position(|&x| x == l))
        .unwrap_or(0);
    let idx = Select::with_theme(&ColorfulTheme::default())
        .with_prompt("Keyboard layout")
        .items(layouts)
        .default(default_idx)
        .interact()?;
    Ok(layouts[idx].to_owned())
}

fn pick_dotfiles_source(existing: Option<&UserConfig>) -> Result<Option<String>> {
    let default = existing
        .and_then(|c| c.dotfiles.source.as_deref())
        .unwrap_or("");
    let source: String = Input::with_theme(&ColorfulTheme::default())
        .with_prompt("Dotfiles source URL (leave empty to skip)")
        .with_initial_text(default)
        .allow_empty(true)
        .interact_text()?;
    Ok((!source.is_empty()).then_some(source))
}

fn render_config(
    all_features: &[(String, Option<String>)],
    selected: &[String],
    layout: &str,
    source: Option<&str>,
) -> String {
    let mut out = String::new();
    out.push_str(&format!(
        "schema_version = {}\n\n",
        kaizen_core::CURRENT_SCHEMA_VERSION
    ));
    for (name, _) in all_features {
        let enabled = selected.contains(name);
        out.push_str(&format!("[features.{name}]\nenabled = {enabled}\n\n"));
    }
    out.push_str(&format!("[settings]\nlayout = {}\n\n", toml_string(layout)));
    out.push_str("[dotfiles]\nbackend = \"chezmoi\"\n");
    if let Some(s) = source.filter(|s| !s.is_empty()) {
        out.push_str(&format!("source = {}\n", toml_string(s)));
    }
    out
}

fn toml_string(s: &str) -> String {
    toml::Value::String(s.to_owned()).to_string()
}

fn write_config(path: &Path, content: &str) -> Result<bool> {
    if path.exists() {
        let overwrite = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt(format!("{} already exists — overwrite?", path.display()))
            .default(false)
            .interact()?;
        if !overwrite {
            println!("  Aborted.");
            return Ok(false);
        }
    }
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(path, content)?;
    Ok(true)
}

fn print_next_steps(path: &Path) {
    output::item_ok(&format!("Config written to {}", path.display()));
    println!();
    println!("  Next steps:");
    println!("    {}  doctor", "kaizen".bold().green());
    println!("    {}  plan", "kaizen".bold().green());
    println!();
}
