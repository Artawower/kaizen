use std::path::{Path, PathBuf};

use crate::{output, selector};
use anyhow::{Context, Result};
use dialoguer::{theme::ColorfulTheme, Confirm, Input, Select};
use kaizen_core::{KaizenEngine, UserConfig};

pub fn run(explicit_features_dir: Option<&Path>, config_path: &Path) -> Result<()> {
    output::page_header("setup");

    let existing = if config_path.exists() {
        kaizen_core::config::load(config_path).ok()
    } else {
        None
    };

    let dotfiles_url = pick_dotfiles_url(existing.as_ref())?;
    let source_dir = bootstrap_chezmoi(&dotfiles_url)?;

    let features_dir = resolve_features_dir(explicit_features_dir, &source_dir);
    let engine = KaizenEngine::new(&features_dir);

    let features = engine.list_features_with_meta()?;
    let Some(selected) = pick_features(&features, existing.as_ref())? else {
        return Ok(());
    };
    let layout = pick_layout(existing.as_ref())?;

    let toml = render_config(&features, &selected, &layout, &dotfiles_url);
    if write_config(config_path, &toml)? {
        prompt_next_action(&engine, config_path)?;
    }
    Ok(())
}

fn pick_dotfiles_url(existing: Option<&UserConfig>) -> Result<String> {
    let default = existing
        .and_then(|c| c.dotfiles.source.as_deref())
        .unwrap_or(kaizen_core::DEFAULT_DOTFILES_SOURCE);
    let url: String = Input::with_theme(&ColorfulTheme::default())
        .with_prompt("Dotfiles repository URL")
        .with_initial_text(default)
        .interact_text()?;
    Ok(url)
}

fn bootstrap_chezmoi(url: &str) -> Result<PathBuf> {
    let existing = kaizen_core::chezmoi::standalone_source_dir()?;

    if let Some(ref source) = existing {
        let remote = kaizen_core::chezmoi::current_remote(source)?;
        if remote
            .as_deref()
            .map(|r| kaizen_core::chezmoi::remotes_match(r, url))
            .unwrap_or(false)
        {
            output::item_ok("chezmoi already initialized with matching remote");
            return Ok(source.clone());
        }
        let prompt = match &remote {
            Some(r) => format!("chezmoi source uses {r:?} \u{2014} replace with {url:?}?"),
            None => {
                format!("chezmoi source exists without a remote \u{2014} replace with {url:?}?")
            }
        };
        let confirmed = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt(prompt)
            .default(false)
            .interact()?;
        if !confirmed {
            anyhow::bail!("setup cancelled \u{2014} existing chezmoi source unchanged");
        }
    }

    let backup: Option<(PathBuf, PathBuf)> = match &existing {
        Some(source) => {
            let b = kaizen_core::chezmoi::backup_source_dir(source)?;
            output::item_warn(&format!("backed up existing source to {}", b.display()));
            Some((source.clone(), b))
        }
        None => None,
    };

    output::item("cloning dotfiles via chezmoi init\u{2026}");
    if let Err(e) = kaizen_core::chezmoi::init_source(url) {
        if let Some((ref source, ref b)) = backup {
            output::item_warn("init failed \u{2014} restoring backup\u{2026}");
            let _ = std::fs::rename(b, source);
        }
        return Err(e.into());
    }

    let new_source = kaizen_core::chezmoi::standalone_source_dir()?
        .context("chezmoi init succeeded but source-path not found")?;

    let kaizen_dir = new_source.join(kaizen_core::manifest::KAIZEN_DIR);
    let manifest_result = kaizen_core::manifest::load(&kaizen_dir)
        .and_then(|m| kaizen_core::manifest::validate(&m).map(|_| ()));
    if let Err(e) = manifest_result {
        if let Some((ref source, ref b)) = backup {
            output::item_warn("manifest invalid \u{2014} restoring previous source\u{2026}");
            let _ = std::fs::remove_dir_all(&new_source);
            let _ = std::fs::rename(b, source);
        }
        return Err(e.into());
    }

    Ok(new_source)
}

fn resolve_features_dir(explicit: Option<&Path>, source_dir: &Path) -> PathBuf {
    if let Some(dir) = explicit {
        return dir.to_owned();
    }
    let candidate = source_dir
        .join(kaizen_core::manifest::KAIZEN_DIR)
        .join(kaizen_core::manifest::FEATURES_SUBDIR);
    if candidate.is_dir() {
        return candidate;
    }
    PathBuf::from("features")
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

fn render_config(
    all_features: &[(String, Option<String>)],
    selected: &[String],
    layout: &str,
    dotfiles_source: &str,
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
    out.push_str(&format!("source = {}\n", toml_string(dotfiles_source)));
    out
}

fn toml_string(s: &str) -> String {
    toml::Value::String(s.to_owned()).to_string()
}

fn write_config(path: &Path, content: &str) -> Result<bool> {
    if path.exists() {
        let overwrite = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt(format!(
                "{} already exists \u{2014} overwrite?",
                path.display()
            ))
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

fn prompt_next_action(engine: &KaizenEngine, config_path: &Path) -> Result<()> {
    output::item_ok(&format!("Config written to {}", config_path.display()));
    println!();

    let choices = &[
        "sync   \u{2014} install packages + apply dotfiles",
        "plan   \u{2014} preview what would happen",
        "skip   \u{2014} I'll do it manually",
    ];
    let idx = Select::with_theme(&ColorfulTheme::default())
        .with_prompt("What next?")
        .items(choices)
        .default(0)
        .interact()?;

    println!();
    match idx {
        0 => super::sync::run(engine, config_path, false),
        1 => super::plan::run(engine, config_path, false),
        _ => Ok(()),
    }
}
