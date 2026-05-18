use std::path::{Path, PathBuf};

use anyhow::{bail, Result};
use kaizen_core::{
    chezmoi::merge_kaizen_data_with, discover_variants, read_kaizen_data, KaizenData, Stability,
    TargetOs, VariantResolver,
};
use owo_colors::OwoColorize;

use crate::{chezmoi::StdChezmoiClient, filesystem::StdFileSystem, output, paths::StdPathProvider};
use kaizen_core::{chezmoi_client::ChezmoiClient as _, PathProvider as _};

pub fn run_list(
    slot_filter: Option<&str>,
    show_experimental: bool,
    features_dir: Option<&Path>,
) -> Result<()> {
    let (resolver, os) = load_resolver(features_dir)?;

    output::page_header("variant list");

    let slots = match slot_filter {
        Some(s) => vec![s.to_owned()],
        None => resolver.list_slots(),
    };

    if slots.is_empty() {
        output::item("no slots defined");
        return Ok(());
    }

    let data = load_data()?;
    let selections = &data.variants;

    for slot in &slots {
        output::header(slot);
        let all = resolver.list_variants(slot);
        let eligible: Vec<_> = resolver.filter_by_os(&os, all);
        let visible: Vec<_> = if show_experimental {
            eligible
        } else {
            resolver.filter_by_stability(false, eligible)
        };

        if visible.is_empty() {
            output::item("  no variants available on this OS");
            continue;
        }

        let effective = resolver.effective(slot, &os, selections);
        let active_id = effective.map(|v| v.id.as_str());

        println!(
            "  {:<20} {:<14} {:<8} {}",
            "variant".bold().dimmed(),
            "stability".bold().dimmed(),
            "default".bold().dimmed(),
            "active".bold().dimmed(),
        );

        for variant in &visible {
            let active_marker = if Some(variant.id.as_str()) == active_id {
                "●".green().to_string()
            } else {
                " ".to_owned()
            };
            let stability_str = match variant.stability {
                Stability::Stable => variant.stability.as_str().to_owned(),
                Stability::Experimental => variant.stability.as_str().yellow().to_string(),
            };
            println!(
                "  {} {:<19} {:<22} {:<8} {}",
                active_marker,
                variant.id,
                stability_str,
                if variant.default { "yes" } else { "" },
                variant.title.as_deref().unwrap_or(""),
            );
        }
    }
    Ok(())
}

pub fn run_show(slot: &str, variant_id: &str, features_dir: Option<&Path>) -> Result<()> {
    let (resolver, _) = load_resolver(features_dir)?;
    let variant = resolver
        .list_variants(slot)
        .into_iter()
        .find(|v| v.id == variant_id)
        .ok_or_else(|| anyhow::anyhow!("variant '{variant_id}' not found in slot '{slot}'"))?;

    output::page_header(&format!("variant: {slot} / {variant_id}"));
    output::kv("id", &variant.id);
    output::kv("slot", &variant.slot);
    output::kv("stability", variant.stability.as_str());
    output::kv("default", if variant.default { "yes" } else { "no" });
    output::kv("platforms", &variant.platforms.join(", "));
    if let Some(title) = &variant.title {
        output::kv("title", title);
    }
    if !variant.provides.dotfile_paths.is_empty() {
        let paths: Vec<_> = variant
            .provides
            .dotfile_paths
            .iter()
            .map(|p| p.display().to_string())
            .collect();
        output::kv("dotfile_paths", &paths.join(", "));
    }
    if !variant.provides.nix_modules.is_empty() {
        let modules: Vec<_> = variant
            .provides
            .nix_modules
            .iter()
            .map(|p| p.display().to_string())
            .collect();
        output::kv("nix_modules", &modules.join(", "));
    }
    Ok(())
}

pub fn run_set(
    slot: &str,
    variant_id: &str,
    allow_experimental: bool,
    features_dir: Option<&Path>,
) -> Result<()> {
    let (resolver, os) = load_resolver(features_dir)?;

    let variant = resolver
        .list_variants(slot)
        .into_iter()
        .find(|v| v.id == variant_id)
        .ok_or_else(|| anyhow::anyhow!("variant '{variant_id}' not found in slot '{slot}'"))?;

    let family = os.platform_family();
    if !variant.platforms.is_empty() && !variant.platforms.iter().any(|p| p == family) {
        bail!(
            "variant '{variant_id}' does not support the current OS ({family})\n  \
             supported: {}",
            variant.platforms.join(", ")
        );
    }

    if variant.stability == Stability::Experimental && !allow_experimental {
        bail!(
            "variant '{variant_id}' is experimental.\n  \
             Use --experimental to confirm you want to activate it.\n  \
             Run 'kaizen variant list --experimental' to see all available variants."
        );
    }

    let mut data = load_data()?;
    data.variants.insert(slot.to_owned(), variant_id.to_owned());

    let plan = data.to_plan();
    let data_path = data_toml_path()?;
    let merged = merge_kaizen_data_with(&data_path, &plan, &StdFileSystem)?;
    std::fs::write(&data_path, merged)?;

    output::item_ok(&format!("set {slot} = {variant_id}"));
    output::item("run 'kaizen sync' to apply");
    Ok(())
}

pub fn run_reset(slot: &str) -> Result<()> {
    let mut data = load_data()?;
    let removed = data.variants.remove(slot).is_some();
    if !removed {
        output::item_warn(&format!("slot '{slot}' had no explicit selection"));
        return Ok(());
    }

    let plan = data.to_plan();
    let data_path = data_toml_path()?;
    let merged = merge_kaizen_data_with(&data_path, &plan, &StdFileSystem)?;
    std::fs::write(&data_path, merged)?;

    output::item_ok(&format!("reset {slot} to default"));
    output::item("run 'kaizen sync' to apply");
    Ok(())
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn load_resolver(features_dir: Option<&Path>) -> Result<(VariantResolver, TargetOs)> {
    let dir = match features_dir {
        Some(d) => d.to_owned(),
        None => default_features_dir()?,
    };
    let os = TargetOs::detect();
    let variants = discover_variants(&dir, &StdFileSystem)?;
    Ok((VariantResolver::new(variants), os))
}

/// Resolve the features directory using the following priority:
///
/// 1. Explicit `--dir` argument (handled by caller via `features_dir` param).
/// 2. Chezmoi source path → parent (repo root) → `features/`.
/// 3. Fallback: `~/.config/kaizen/features/` (deployed mode).
fn default_features_dir() -> Result<PathBuf> {
    if let Ok(Some(source)) = StdChezmoiClient.source_path() {
        let repo_root = source.parent().unwrap_or(&source);
        let candidate = repo_root.join("features");
        if candidate.exists() {
            return Ok(candidate);
        }
    }
    let config = StdPathProvider
        .config_dir()
        .ok_or_else(|| anyhow::anyhow!("cannot determine config directory"))?;
    let fallback = config.join("kaizen").join("features");
    if !fallback.exists() {
        bail!(
            "features directory not found.\n  \
             Tried: chezmoi source parent/features, {}\n  \
             Use --dir to specify the path explicitly.",
            fallback.display()
        );
    }
    Ok(fallback)
}

fn data_toml_path() -> Result<PathBuf> {
    let config = StdPathProvider
        .config_dir()
        .ok_or_else(|| anyhow::anyhow!("cannot determine config directory"))?;
    Ok(config.join("kaizen").join("data.toml"))
}

fn load_data() -> Result<KaizenData> {
    let path = data_toml_path()?;
    Ok(read_kaizen_data(&path, &StdFileSystem)?)
}
