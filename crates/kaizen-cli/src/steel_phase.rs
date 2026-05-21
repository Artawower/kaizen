use std::path::{Path, PathBuf};

use kaizen_core::steel_module::{
    load_all, load_user_overrides, resolve_group_conflicts, SteelEngine,
};

/// Resolve the chezmoi source directory, or `None` if unavailable.
fn chezmoi_source() -> Option<PathBuf> {
    use kaizen_core::chezmoi_client::ChezmoiClient as _;
    crate::chezmoi::StdChezmoiClient
        .source_path()
        .ok()
        .flatten()
}

/// Locate the Steel features directory.
///
/// Checks (in order):
///   1. `<chezmoi-source>/kaizen/features/` (production)
///   2. `<cwd>/dotfiles/kaizen/features/`   (dev / repo checkout)
pub fn steel_features_dir() -> Option<PathBuf> {
    if let Some(src) = chezmoi_source() {
        let p = src.join("kaizen").join("features");
        if p.exists() {
            return Some(p);
        }
    }
    let dev = std::env::current_dir()
        .ok()?
        .join("dotfiles")
        .join("kaizen")
        .join("features");
    dev.exists().then_some(dev)
}

/// Build an initial context for `SteelEngine::new` from available environment.
///
/// Always includes `chezmoi_source` when the chezmoi source is resolvable.
/// Callers should insert `dry_run` before passing to `SteelEngine::new`.
pub fn build_context() -> std::collections::HashMap<String, String> {
    let mut ctx = std::collections::HashMap::new();
    if let Some(src) = chezmoi_source() {
        ctx.insert(
            "chezmoi_source".to_string(),
            src.to_string_lossy().into_owned(),
        );
    }
    ctx
}

/// Load all feature modules, check group conflicts, apply user overrides,
/// run phase-2 callbacks, and write `/tmp/kaizen-runtime.json`.
///
/// `dry_run` is forwarded into the Steel context so `generate-file!` and
/// `config-dir!` skip actual disk writes.  Errors are returned as `Err` —
/// callers must NOT proceed to chezmoi apply when this fails.
pub fn run_steel_phase(features_dir: &Path, dry_run: bool) -> anyhow::Result<()> {
    let mut ctx = std::collections::HashMap::new();
    ctx.insert("dry_run".to_string(), dry_run.to_string());
    // chezmoi_source makes config-dir! write to the correct destination.
    if let Some(src) = chezmoi_source() {
        ctx.insert(
            "chezmoi_source".to_string(),
            src.to_string_lossy().into_owned(),
        );
    }

    let mut engine = SteelEngine::new(ctx);

    load_all(&mut engine, features_dir)
        .map_err(|errs| anyhow::anyhow!("steel load errors: {}", errs.join("; ")))?;

    engine
        .with_state(resolve_group_conflicts)
        .map_err(|conflicts| anyhow::anyhow!("group conflicts: {}", conflicts.join("; ")))?;

    let user_dir = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join(".config/kaizen/user");
    if let Err(errs) = load_user_overrides(&mut engine, &user_dir) {
        for e in &errs {
            eprintln!("Warning: user override error: {e}");
        }
    }

    engine
        .run_apply_phase()
        .map_err(|e| anyhow::anyhow!("{e}"))?;

    engine
        .write_runtime_json(Path::new("/tmp/kaizen-runtime.json"))
        .ok();
    Ok(())
}
