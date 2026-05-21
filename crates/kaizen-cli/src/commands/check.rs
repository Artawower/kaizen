use std::path::Path;

use anyhow::{anyhow, Result};
use kaizen_core::steel_module::{
    discover_modules, load_all, load_user_overrides, resolve_group_conflicts, SteelEngine,
};

const RUNTIME_JSON_PATH: &str = "/tmp/kaizen-runtime.json";

/// Load all `features/*/module.scm` modules (respecting enabled.toml), check
/// for group conflicts, run phase 2, validate bindings, write runtime.json.
///
/// Passes `dry_run=true` in context so generate-file! only prints, not writes.
pub fn run(features_dir: &Path) -> Result<()> {
    let mut ctx = std::collections::HashMap::new();
    ctx.insert("dry_run".to_string(), "true".to_string());
    let mut engine = SteelEngine::new(ctx);

    let modules = discover_modules(features_dir);
    if modules.is_empty() {
        println!("No modules found under {}", features_dir.display());
        return Ok(());
    }

    // Phase 1: load enabled feature modules.
    let load_errors = load_all(&mut engine, features_dir)
        .err()
        .unwrap_or_default();

    engine.with_state(|s| {
        println!("Modules  : {}", s.modules.len());
        for m in &s.modules {
            println!("  - {} (group: {:?})", m.name, m.group);
        }
        println!("Actions  : {}", s.actions.len());
        println!("Bindings : {}", s.bindings.len());
        println!("Packages : {}", s.packages.len());
        if !s.globals.is_empty() {
            println!("Globals  : {}", s.globals.len());
        }
        if !s.overrides.is_empty() {
            println!("Overrides: {}", s.overrides.len());
        }
    });

    // Group conflict check — must pass before running apply phase.
    let conflict_errors: Vec<String> = engine
        .with_state(resolve_group_conflicts)
        .err()
        .unwrap_or_default();
    if !conflict_errors.is_empty() {
        for e in &conflict_errors {
            eprintln!("ERROR (group conflict): {e}");
        }
        return Err(anyhow!(
            "group conflicts detected — run `kaizen configure` to resolve"
        ));
    }

    // Load user overrides (~/.config/kaizen/user/*.scm). Non-fatal.
    let user_dir = home_dir().join(".config/kaizen/user");
    if let Err(errs) = load_user_overrides(&mut engine, &user_dir) {
        for e in &errs {
            eprintln!("WARNING: {e}");
        }
    }

    // Phase 2: resolve hooks + run on-apply! callbacks.
    let apply_error = engine.run_apply_phase().err();

    let invalid_bindings = engine.validate_bindings();

    let all_errors: Vec<String> = load_errors
        .into_iter()
        .chain(apply_error)
        .chain(invalid_bindings)
        .collect();

    // Write runtime snapshot (best-effort).
    match engine.write_runtime_json(std::path::Path::new(RUNTIME_JSON_PATH)) {
        Ok(()) => println!("runtime.json → {RUNTIME_JSON_PATH}"),
        Err(e) => eprintln!("WARNING: could not write runtime.json: {e}"),
    }

    if all_errors.is_empty() {
        println!("OK");
        return Ok(());
    }

    for e in &all_errors {
        eprintln!("ERROR: {e}");
    }
    Err(anyhow!("check failed with {} error(s)", all_errors.len()))
}

fn home_dir() -> std::path::PathBuf {
    std::env::var_os("HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from("/tmp"))
}
