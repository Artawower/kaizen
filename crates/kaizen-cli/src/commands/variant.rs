use std::path::{Path, PathBuf};

use crate::{chezmoi::StdChezmoiClient, filesystem::StdFileSystem, output, paths::StdPathProvider};
use anyhow::{bail, Result};
use kaizen_core::{chezmoi_client::ChezmoiClient as _, PathProvider as _};
use kaizen_core::{discover_variants, KaizenEngine, Stability, TargetOs, VariantResolver};

pub fn run_set(
    slot: &str,
    variant_id: &str,
    allow_experimental: bool,
    features_dir: Option<&Path>,
    engine: &KaizenEngine,
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
             Use --experimental to confirm you want to activate it."
        );
    }

    let mut selections = engine.current_variant_selections()?;
    selections.insert(slot.to_owned(), variant_id.to_owned());
    engine.apply_variant_selections(selections)?;

    output::item_ok(&format!("set {slot} = {variant_id}"));
    output::item("run 'kaizen sync' to apply");
    Ok(())
}

pub fn run_reset(slot: &str, engine: &KaizenEngine) -> Result<()> {
    let mut selections = engine.current_variant_selections()?;
    let removed = selections.remove(slot).is_some();
    if !removed {
        output::item_warn(&format!("slot '{slot}' had no explicit selection"));
        return Ok(());
    }

    engine.apply_variant_selections(selections)?;

    output::item_ok(&format!("reset {slot} to default"));
    output::item("run 'kaizen sync' to apply");
    Ok(())
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn load_resolver(features_dir: Option<&Path>) -> Result<(VariantResolver, TargetOs)> {
    let dir = resolve_features_dir(features_dir)?;
    let os = TargetOs::detect();
    let variants = discover_variants(&dir, &StdFileSystem)?;
    Ok((VariantResolver::new(variants), os))
}

fn resolve_features_dir(override_dir: Option<&Path>) -> Result<PathBuf> {
    if let Some(d) = override_dir {
        return Ok(d.to_owned());
    }
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
