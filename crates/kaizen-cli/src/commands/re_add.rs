use anyhow::Result;
use kaizen_core::{steel_module, KaizenEngine};

use crate::{output, steel_phase};

/// Run `on-re-add!` callbacks defined in Steel feature modules.
///
/// Re-adds generated/templated files back into the chezmoi source so they
/// can be committed.
pub fn run(_engine: &KaizenEngine, dry_run: bool) -> Result<()> {
    output::page_header(if dry_run {
        "re-add  (dry-run)"
    } else {
        "re-add"
    });

    let features_dir = steel_phase::steel_features_dir()
        .ok_or_else(|| anyhow::anyhow!("features directory not found"))?;

    let mut ctx = steel_phase::build_context();
    ctx.insert("dry_run".into(), dry_run.to_string());

    let mut steel = kaizen_core::steel_module::SteelEngine::new(ctx);
    steel_module::load_all(&mut steel, &features_dir)
        .map_err(|errs| anyhow::anyhow!("{}", errs.join(", ")))?;

    output::header("re-add");
    steel
        .run_re_add_phase()
        .map_err(|e| anyhow::anyhow!("re-add phase failed: {e}"))?;

    if !dry_run {
        println!();
        output::item_ok("re-add complete");
    }
    Ok(())
}
