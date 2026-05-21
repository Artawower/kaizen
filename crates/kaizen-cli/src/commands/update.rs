use std::path::Path;

use anyhow::Result;
use kaizen_core::{steel_module, KaizenEngine};

use crate::{output, steel_phase};

/// Run `on-update!` callbacks defined in Steel feature modules.
///
/// This replaces the old hook system for update commands.  Version pins are
/// updated by the Steel lambdas; call `jj` / `git commit` afterwards to
/// capture the changes.
pub fn run(
    _engine: &KaizenEngine,
    _config_path: &Path,
    dry_run: bool,
    update_flake: bool,
    _features: Vec<String>,
    _interactive: bool,
) -> Result<()> {
    output::page_header(if dry_run {
        "update  (dry-run)"
    } else {
        "update"
    });

    let features_dir = steel_phase::steel_features_dir()
        .ok_or_else(|| anyhow::anyhow!("features directory not found"))?;

    let mut ctx = steel_phase::build_context();
    ctx.insert("dry_run".into(), dry_run.to_string());
    ctx.insert("update_flake".into(), update_flake.to_string());

    let mut steel = kaizen_core::steel_module::SteelEngine::new(ctx);
    steel_module::load_all(&mut steel, &features_dir)
        .map_err(|errs| anyhow::anyhow!("{}", errs.join(", ")))?;

    output::header("update");
    steel
        .run_update_phase()
        .map_err(|e| anyhow::anyhow!("update phase failed: {e}"))?;

    if !dry_run {
        println!();
        output::item_ok("update complete — commit the updated configurations");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    // Tests avoid `steel::rvals` directly — kaizen-cli does not depend on steel-core.
    // Side-effects are verified through Steel expressions instead.
    use kaizen_core::steel_module::SteelEngine;

    fn fresh() -> SteelEngine {
        SteelEngine::new(Default::default())
    }

    fn ok(e: &mut SteelEngine, code: &str) {
        e.engine.run(code.to_owned()).expect(code);
    }

    #[test]
    fn run_update_phase_executes_callbacks() {
        let mut e = fresh();
        ok(
            &mut e,
            "(define updated #f)\n(on-update! (lambda () (set! updated #t)))",
        );
        e.run_update_phase().expect("update phase must succeed");
        ok(
            &mut e,
            "(if (not updated) (error \"update callback was not called\") #t)",
        );
    }

    #[test]
    fn shell_fn_returns_stdout() {
        let mut e = fresh();
        e.engine
            .run(r#"(shell! "echo hello")"#.to_owned())
            .expect("shell! must succeed");
    }

    #[test]
    fn chezmoi_re_add_dry_run_does_not_exec() {
        let mut ctx = std::collections::HashMap::new();
        ctx.insert("dry_run".into(), "true".into());
        let mut e = SteelEngine::new(ctx);
        // dry_run must short-circuit before calling the chezmoi binary.
        e.engine
            .run(r#"(chezmoi-re-add! "/tmp/nonexistent-kaizen-test")"#.to_owned())
            .expect("dry-run chezmoi-re-add! must not fail");
    }
}
