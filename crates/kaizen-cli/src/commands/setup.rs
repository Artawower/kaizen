use std::path::Path;

use anyhow::Result;
use dialoguer::{theme::ColorfulTheme, Confirm, Input, Select};
use kaizen_core::KaizenEngine;
use owo_colors::OwoColorize;

use crate::{output, selector};

pub fn run(engine: &KaizenEngine, config_path: &Path) -> Result<()> {
    output::page_header("setup");

    let features = engine.list_features_with_meta()?;
    let Some(selected) = pick_features(&features)? else {
        return Ok(());
    };
    let layout = pick_layout()?;
    let dotfiles_source = pick_dotfiles_source()?;

    let toml = render_config(&features, &selected, &layout, dotfiles_source.as_deref());
    if write_config(config_path, &toml)? {
        print_next_steps(config_path);
    }
    Ok(())
}

fn pick_features(features: &[(String, Option<String>)]) -> Result<Option<Vec<String>>> {
    let items = features
        .iter()
        .map(|(name, desc)| selector::Item {
            name: name.clone(),
            desc: desc.clone(),
            selected: true,
        })
        .collect();
    selector::multi_select("Select features", items)
}

fn pick_layout() -> Result<String> {
    let layouts = &["colemak", "qwerty"];
    let idx = Select::with_theme(&ColorfulTheme::default())
        .with_prompt("Keyboard layout")
        .items(layouts)
        .default(0)
        .interact()?;
    Ok(layouts[idx].to_owned())
}

fn pick_dotfiles_source() -> Result<Option<String>> {
    let source: String = Input::with_theme(&ColorfulTheme::default())
        .with_prompt("Dotfiles source URL (leave empty to skip)")
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
