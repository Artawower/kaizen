use std::path::Path;

use anyhow::Result;
use kaizen_core::{steel_module, KaizenEngine};

use crate::{output, steel_phase};

/// Run `on-bump!` callbacks defined in Steel feature modules.
///
/// This replaces the old `bump.toml` manifest system.  Version pins are
/// updated by the Steel lambdas; call `jj` / `git commit` afterwards to
/// capture the changes.
pub fn run(_engine: &KaizenEngine, _config_path: &Path, dry_run: bool) -> Result<()> {
    output::page_header(if dry_run { "bump  (dry-run)" } else { "bump" });

    let features_dir = steel_phase::steel_features_dir()
        .ok_or_else(|| anyhow::anyhow!("features directory not found"))?;

    let mut ctx = steel_phase::build_context();
    ctx.insert("dry_run".into(), dry_run.to_string());

    let mut steel = kaizen_core::steel_module::SteelEngine::new(ctx);
    steel_module::load_all(&mut steel, &features_dir)
        .map_err(|errs| anyhow::anyhow!("{}", errs.join(", ")))?;

    output::header("bump");
    steel
        .run_bump_phase()
        .map_err(|e| anyhow::anyhow!("bump phase failed: {e}"))?;

    if !dry_run {
        println!();
        output::item_ok("bump complete — commit the updated lock files");
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
    fn run_bump_phase_executes_callbacks() {
        let mut e = fresh();
        ok(
            &mut e,
            "(define bumped #f)\n(on-bump! (lambda () (set! bumped #t)))",
        );
        e.run_bump_phase().expect("bump phase must succeed");
        ok(
            &mut e,
            "(if (not bumped) (error \"bump callback was not called\") #t)",
        );
    }

    #[test]
    fn run_re_add_phase_executes_callbacks() {
        let mut e = fresh();
        ok(
            &mut e,
            "(define re-added #f)\n(on-re-add! (lambda () (set! re-added #t)))",
        );
        e.run_re_add_phase().expect("re-add phase must succeed");
        ok(
            &mut e,
            "(if (not re-added) (error \"re-add callback was not called\") #t)",
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
