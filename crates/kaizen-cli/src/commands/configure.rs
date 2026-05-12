use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use dialoguer::{theme::ColorfulTheme, Confirm, Input, Select};
use std::sync::Arc;

use kaizen_core::{
    render_config, resolve_features_dir_from_source, BootstrapStatus, ChezmoiBootstrapper,
    KaizenEngine, UserConfig,
};

use crate::{engine, ensure, filesystem::StdFileSystem, output, paths::StdPathProvider, selector};

/// Run the interactive configuration wizard.
///
/// When `prompt_next` is `true` (standalone `kaizen configure`) the user is
/// offered a "What next?" prompt at the end.  When called from `kaizen install`
/// pass `false` — install handles syncing itself (with `--force`).
pub fn run(
    explicit_features_dir: Option<&Path>,
    config_path: &Path,
    prompt_next: bool,
) -> Result<()> {
    output::page_header("configure");
    ensure::ensure_chezmoi()?;

    let fs = Arc::new(StdFileSystem);
    let existing = if config_path.exists() {
        kaizen_core::config::load_with(config_path, fs.as_ref()).ok()
    } else {
        None
    };

    let dotfiles_url = pick_dotfiles_url(existing.as_ref())?;
    let source_dir = bootstrap_chezmoi(&dotfiles_url)?;

    refresh_feature_cache_from_seed(&source_dir);

    let features_dir =
        resolve_features_dir_from_source(explicit_features_dir, &source_dir, fs.as_ref());
    let use_cache = explicit_features_dir.is_none();
    let engine = engine::build(features_dir, use_cache);

    let features = engine.list_features_with_meta()?;
    let Some(selected) = pick_features(&features, existing.as_ref())? else {
        return Ok(());
    };
    let layout = pick_layout(existing.as_ref())?;

    let toml = render_config(&features, &selected, &layout, &dotfiles_url);
    if write_config(config_path, &toml)? && prompt_next {
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
    let bootstrapper = ChezmoiBootstrapper::new(
        Box::new(crate::chezmoi::StdChezmoiClient),
        Box::new(StdFileSystem),
    );
    match bootstrapper.check(url)? {
        BootstrapStatus::AlreadyUpToDate(source) => {
            output::item_ok("chezmoi already initialized with matching remote");
            Ok(source)
        }
        BootstrapStatus::Conflict {
            source,
            current_remote,
        } => {
            let prompt = match &current_remote {
                Some(r) => format!("chezmoi source uses {r:?} — replace with {url:?}?"),
                None => {
                    format!("chezmoi source exists without a remote — replace with {url:?}?")
                }
            };
            let confirmed = Confirm::with_theme(&ColorfulTheme::default())
                .with_prompt(prompt)
                .default(false)
                .interact()?;
            if !confirmed {
                anyhow::bail!("configure cancelled — existing chezmoi source unchanged");
            }
            output::item("cloning dotfiles via chezmoi init…");
            let (new_source, backup) = bootstrapper
                .backup_and_reinit(url, &source)
                .context("chezmoi init failed")?;
            output::item_warn(&format!(
                "backed up existing source to {}",
                backup.display()
            ));
            Ok(new_source)
        }
        BootstrapStatus::InitRequired => {
            output::item("cloning dotfiles via chezmoi init…");
            bootstrapper.init(url).context("chezmoi init failed")
        }
        BootstrapStatus::StaleSource {
            git_root,
            expected_source,
        } => {
            output::item(&format!(
                "dotfiles source is outdated — pulling {} …",
                git_root.display()
            ));
            use kaizen_core::ChezmoiClient as _;
            crate::chezmoi::StdChezmoiClient
                .pull_source(&git_root) // adapter locates git root & handles symlink check
                .context("failed to update dotfiles source")?;
            if !expected_source.exists() {
                anyhow::bail!(
                    "pull succeeded but expected source still missing: {}\n\
                     Check .chezmoiroot or dotfiles repository layout.",
                    expected_source.display()
                );
            }
            output::item_ok("dotfiles source updated");
            Ok(expected_source)
        }
    }
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

/// Copy the committed `feature-meta.json` seed from the chezmoi source to
/// `~/.config/kaizen/feature-meta.json`. Always overwrites the existing cache
/// so that switching dotfiles sources never leaves a stale feature list in the
/// wizard. The live home-manager activation will overwrite this seed again
/// after the first `home-manager switch`.
fn refresh_feature_cache_from_seed(source_dir: &Path) {
    use kaizen_core::PathProvider as _;
    let Some(config_dir) = StdPathProvider.config_dir() else {
        return;
    };
    let target = config_dir.join("kaizen").join("feature-meta.json");
    let seed = source_dir
        .join("dot_config")
        .join("kaizen")
        .join("feature-meta.json");
    if !seed.exists() {
        return;
    }
    let _ = std::fs::create_dir_all(target.parent().unwrap());
    let _ = std::fs::copy(&seed, &target);
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

fn prompt_next_action(engine: &KaizenEngine, config_path: &Path) -> Result<()> {
    output::item_ok(&format!("Config written to {}", config_path.display()));
    println!();

    let choices = &[
        "sync   — install packages + apply dotfiles",
        "plan   — preview what would happen",
        "skip   — I'll do it manually",
    ];
    let idx = Select::with_theme(&ColorfulTheme::default())
        .with_prompt("What next?")
        .items(choices)
        .default(0)
        .interact()?;

    println!();
    match idx {
        0 => super::sync::run(engine, config_path, false, false),
        1 => super::plan::run(engine, config_path, false),
        _ => Ok(()),
    }
}
