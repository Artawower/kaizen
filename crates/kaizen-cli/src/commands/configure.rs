use std::collections::HashMap;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use dialoguer::{theme::ColorfulTheme, Confirm, Input, Select};

use kaizen_core::{
    steel_module::{
        discover_modules, read_enabled_list, write_enabled_list, ModuleDecl, SteelEngine,
    },
    BootstrapStatus, ChezmoiBootstrapper,
};

use crate::{ensure, filesystem::StdFileSystem, output, selector};

/// Run the interactive configuration wizard.
///
/// `prompt_next=true` (standalone `kaizen configure`) offers a "What next?"
/// prompt at the end.  `kaizen install` passes `false`.
/// `allow_experimental=true` shows modules with `stability = 'experimental'`.
pub fn run(prompt_next: bool, allow_experimental: bool) -> Result<()> {
    output::page_header("configure");
    ensure::ensure_chezmoi()?;

    let dotfiles_url = pick_dotfiles_url()?;
    let source_dir = bootstrap_chezmoi(&dotfiles_url)?;
    let features_dir = source_dir.join("kaizen").join("features");

    if features_dir.exists() {
        let engine = load_all_modules(&features_dir);
        configure_features(&engine, &features_dir, allow_experimental)?;
        configure_settings(&engine, &features_dir)?;
    }

    if prompt_next {
        prompt_next_action()?;
    }

    Ok(())
}

// ── Feature selection (Steel-based) ──────────────────────────────────────────

/// Present the feature wizard in two passes:
/// 1. For each declared group: `Select` prompt → exactly one module (or none).
/// 2. For ungrouped modules: `MultiSelect`.
/// Writes the final set to `enabled.toml`.
fn configure_features(
    engine: &SteelEngine,
    features_dir: &Path,
    allow_experimental: bool,
) -> Result<()> {
    let current_enabled = read_enabled_list(features_dir);
    let current_enabled = current_enabled.as_deref().unwrap_or(&[]);

    let (groups, ungrouped) = partition_modules(engine, allow_experimental);

    if groups.is_empty() && ungrouped.is_empty() {
        output::item_warn("no features found in features directory");
        return Ok(());
    }

    let mut selected: Vec<String> = vec![];

    if !groups.is_empty() {
        output::header("feature groups");
        for (group, members) in &groups {
            let chosen = pick_group_module(group, members, current_enabled)?;
            if let Some(name) = chosen {
                selected.push(name);
            }
        }
    }

    if !ungrouped.is_empty() {
        output::header("features");
        let items = ungrouped
            .iter()
            .map(|m| selector::Item {
                name: m.name.clone(),
                desc: Some(module_desc(m)),
                selected: current_enabled.contains(&m.name),
            })
            .collect();
        if let Some(extras) = selector::multi_select("Select features to enable", items)? {
            selected.extend(extras);
        }
    }

    write_enabled_list(features_dir, &selected)
        .map_err(|e| anyhow::anyhow!("failed to write enabled.toml: {e}"))?;
    output::item_ok(&format!(
        "saved enabled.toml ({} features enabled)",
        selected.len()
    ));
    Ok(())
}

/// Partition loaded modules into (sorted groups, ungrouped).
/// Modules with `stability = "experimental"` are excluded unless the flag is set.
fn partition_modules(
    engine: &SteelEngine,
    allow_experimental: bool,
) -> (Vec<(String, Vec<ModuleDecl>)>, Vec<ModuleDecl>) {
    engine.with_state(|s| {
        let mut by_group: HashMap<String, Vec<ModuleDecl>> = HashMap::new();
        let mut ungrouped: Vec<ModuleDecl> = vec![];

        for m in &s.modules {
            if m.stability == "experimental" && !allow_experimental {
                continue;
            }
            match &m.group {
                Some(g) => by_group.entry(g.clone()).or_default().push(m.clone()),
                None => ungrouped.push(m.clone()),
            }
        }

        let mut groups: Vec<(String, Vec<ModuleDecl>)> = by_group.into_iter().collect();
        groups.sort_by(|a, b| a.0.cmp(&b.0));
        (groups, ungrouped)
    })
}

/// Prompt the user to pick exactly one module from `members` for `group`.
/// Returns `None` if the user picks "none".
fn pick_group_module(
    group: &str,
    members: &[ModuleDecl],
    current_enabled: &[String],
) -> Result<Option<String>> {
    let none_label = "none (skip this group)".to_string();
    let labels: Vec<String> = members
        .iter()
        .map(|m| {
            if m.description.is_empty() {
                m.name.clone()
            } else {
                format!("{}  — {}", m.name, m.description)
            }
        })
        .chain(std::iter::once(none_label))
        .collect();

    let none_idx = labels.len() - 1;
    let default_idx = members
        .iter()
        .position(|m| current_enabled.contains(&m.name))
        .unwrap_or(none_idx);

    let idx = Select::with_theme(&ColorfulTheme::default())
        .with_prompt(format!("  {group}"))
        .items(&labels)
        .default(default_idx)
        .interact()?;

    Ok((idx < members.len()).then(|| members[idx].name.clone()))
}

/// Build a short description string shown next to a feature in the multiselect.
fn module_desc(m: &ModuleDecl) -> String {
    let mut parts = Vec::new();
    if !m.description.is_empty() {
        parts.push(m.description.clone());
    }
    if m.stability != "stable" {
        parts.push(format!("({})", m.stability));
    }
    parts.join("  ")
}

// ── Settings ──────────────────────────────────────────────────────────────────

/// Read current layout / font-size from Steel globals (set by `settings/module.scm`),
/// prompt the user for overrides, then regenerate `settings/module.scm`.
fn configure_settings(engine: &SteelEngine, features_dir: &Path) -> Result<()> {
    output::header("settings");

    let default_layout = engine.with_state(|s| {
        s.globals
            .get("layout")
            .cloned()
            .unwrap_or_else(|| "colemak".to_string())
    });
    let default_font: f64 = engine.with_state(|s| {
        s.globals
            .get("ui/font-size")
            .and_then(|v| v.parse().ok())
            .unwrap_or(14.0)
    });

    let layout = pick_layout(&default_layout)?;
    let font_size = pick_font_size(default_font)?;
    write_settings_module(features_dir, &layout, font_size)?;
    output::item_ok("settings saved to features/settings/module.scm");
    Ok(())
}

fn write_settings_module(features_dir: &Path, layout: &str, font_size: f64) -> Result<()> {
    let path = features_dir.join("settings").join("module.scm");
    std::fs::create_dir_all(path.parent().expect("path has parent"))?;
    let content = format!(
        r#"(declare-module "settings" :group 'system :description "Global settings")

(set-global! :layout       "{layout}")
(set-global! :ui/font-size "{font_size}")
(set-global! :ui/theme     "catppuccin-mocha")

(on-bump!
  (lambda ()
    (shell! "~/.config/scripts/mise-bump")))

(on-re-add!
  (lambda ()
    (chezmoi-re-add! "~/.config/mise.lock")))
"#
    );
    std::fs::write(&path, content)?;
    Ok(())
}

// ── Module loading ────────────────────────────────────────────────────────────

/// Load every `module.scm` under `features_dir/*/module.scm` into a fresh engine.
/// Ignores `enabled.toml` — all modules are loaded for metadata discovery.
/// Soft-warns on load failures; does not bail.
fn load_all_modules(features_dir: &Path) -> SteelEngine {
    let mut engine = SteelEngine::new(Default::default());
    for (path, name) in discover_modules(features_dir) {
        if let Err(e) = engine.load_module(&path, &name) {
            output::item_warn(&format!("module '{name}' failed to load: {e}"));
        }
    }
    engine
}

// ── Next-action prompt ────────────────────────────────────────────────────────

fn prompt_next_action() -> Result<()> {
    let choices = &[
        "apply  — apply dotfiles now",
        "skip   — I'll do it manually",
    ];
    let idx = Select::with_theme(&ColorfulTheme::default())
        .with_prompt("What next?")
        .items(choices)
        .default(0)
        .interact()?;

    if idx == 0 {
        use kaizen_core::chezmoi_client::ChezmoiClient as _;
        crate::chezmoi::StdChezmoiClient
            .apply(false)
            .map_err(|e| anyhow::anyhow!("{e}"))?;
    }
    Ok(())
}

// ── Pickers ───────────────────────────────────────────────────────────────────

/// Prompt for the dotfiles repository URL.
/// The default is the current chezmoi remote (if available) or the project default.
fn pick_dotfiles_url() -> Result<String> {
    let default = chezmoi_current_remote()
        .unwrap_or_else(|| kaizen_core::DEFAULT_DOTFILES_SOURCE.to_string());
    let url: String = Input::with_theme(&ColorfulTheme::default())
        .with_prompt("Dotfiles repository URL")
        .with_initial_text(&default)
        .interact_text()?;
    Ok(url)
}

fn chezmoi_current_remote() -> Option<String> {
    use kaizen_core::chezmoi_client::ChezmoiClient as _;
    let src = crate::chezmoi::StdChezmoiClient.source_path().ok()??;
    crate::chezmoi::StdChezmoiClient.current_remote(&src).ok()?
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
                None => format!("chezmoi source exists without a remote — replace with {url:?}?"),
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
                .pull_source(&git_root)
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

fn pick_layout(default: &str) -> Result<String> {
    let layouts = &["colemak", "qwerty"];
    let default_idx = layouts.iter().position(|&x| x == default).unwrap_or(0);
    let idx = Select::with_theme(&ColorfulTheme::default())
        .with_prompt("Keyboard layout")
        .items(layouts)
        .default(default_idx)
        .interact()?;
    Ok(layouts[idx].to_owned())
}

fn pick_font_size(default: f64) -> Result<f64> {
    let font_size = Input::with_theme(&ColorfulTheme::default())
        .with_prompt("UI font size")
        .with_initial_text(default.to_string())
        .interact_text()?;
    Ok(font_size)
}
