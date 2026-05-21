use std::collections::HashMap;
use std::path::{Path, PathBuf};

use super::engine::SteelEngine;
use super::state::KaizenState;

// ── Module discovery ──────────────────────────────────────────────────────────

/// Discover all `module.scm` files under `features_dir/*/module.scm`.
///
/// Returns `(path, module_name)` pairs sorted by module name.
pub fn discover_modules(features_dir: &Path) -> Vec<(PathBuf, String)> {
    if !features_dir.is_dir() {
        return vec![];
    }

    let mut modules: Vec<(PathBuf, String)> = std::fs::read_dir(features_dir)
        .map(|rd| {
            rd.filter_map(|e| e.ok())
                .filter(|e| e.path().is_dir())
                .filter_map(|e| {
                    let module_path = e.path().join("module.scm");
                    module_path.exists().then(|| {
                        let name = e.file_name().to_string_lossy().into_owned();
                        (module_path, name)
                    })
                })
                .collect()
        })
        .unwrap_or_default();

    modules.sort_by(|a, b| a.1.cmp(&b.1));
    modules
}

// ── Enabled-list management ───────────────────────────────────────────────────

/// Read `features_dir/enabled.toml` if it exists.
///
/// Returns `Some(names)` when the file is present and valid, `None` when the
/// file is absent (meaning "all modules enabled").
pub fn read_enabled_list(features_dir: &Path) -> Option<Vec<String>> {
    let path = features_dir.join("enabled.toml");
    if !path.exists() {
        return None;
    }
    let raw = std::fs::read_to_string(&path).ok()?;
    let table: toml::Table = toml::from_str(&raw).ok()?;
    let arr = table.get("enabled")?.as_array()?;
    Some(
        arr.iter()
            .filter_map(|v| v.as_str().map(str::to_owned))
            .collect(),
    )
}

/// Write `features_dir/enabled.toml` with the given module names.
pub fn write_enabled_list(features_dir: &Path, enabled: &[String]) -> std::io::Result<()> {
    let list: Vec<toml::Value> = enabled
        .iter()
        .map(|s| toml::Value::String(s.clone()))
        .collect();
    let table = toml::Table::from_iter([("enabled".to_string(), toml::Value::Array(list))]);
    let content = toml::to_string_pretty(&toml::Value::Table(table)).unwrap_or_default();
    std::fs::write(features_dir.join("enabled.toml"), content)
}

// ── Loading phases ────────────────────────────────────────────────────────────

/// Load all discovered modules into the engine (phase 1 / Collection).
///
/// If `features_dir/enabled.toml` exists, only modules in the enabled list are
/// loaded.  Returns `Err(errors)` if any module failed; all others continue.
pub fn load_all(engine: &mut SteelEngine, features_dir: &Path) -> Result<(), Vec<String>> {
    let enabled = read_enabled_list(features_dir);
    let modules = discover_modules(features_dir);
    let mut errors = vec![];

    for (path, name) in &modules {
        if let Some(ref list) = enabled {
            if !list.contains(name) {
                continue;
            }
        }
        if let Err(e) = engine.load_module(path, name) {
            errors.push(format!("failed to load module '{name}': {e}"));
        }
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

/// Load all `*.scm` files from `user_dir` in sorted order.
///
/// Non-existent directory is a no-op; individual file errors are collected.
pub fn load_user_overrides(engine: &mut SteelEngine, user_dir: &Path) -> Result<(), Vec<String>> {
    if !user_dir.is_dir() {
        return Ok(());
    }

    let mut files: Vec<PathBuf> = std::fs::read_dir(user_dir)
        .map(|rd| {
            rd.filter_map(|e| e.ok())
                .map(|e| e.path())
                .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("scm"))
                .collect()
        })
        .unwrap_or_default();
    files.sort();

    let mut errors = vec![];
    for path in &files {
        let name = path
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned();
        if let Err(e) = engine.load_module(path, &name) {
            errors.push(format!("failed to load user override '{name}': {e}"));
        }
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

// ── Group conflict resolution ─────────────────────────────────────────────────

/// Check whether multiple loaded modules claim the same `group`.
///
/// Returns `Ok(())` when there are no conflicts, or `Err(messages)` listing
/// each conflict (one message per conflicting group).
pub fn resolve_group_conflicts(state: &KaizenState) -> Result<(), Vec<String>> {
    let mut by_group: HashMap<String, Vec<String>> = HashMap::new();

    for m in &state.modules {
        if let Some(group) = &m.group {
            by_group
                .entry(group.clone())
                .or_default()
                .push(m.name.clone());
        }
    }

    let conflicts: Vec<String> = by_group
        .into_iter()
        .filter(|(_, names)| names.len() > 1)
        .map(|(group, names)| {
            format!(
                "group '{}' claimed by multiple modules: {}",
                group,
                names.join(", ")
            )
        })
        .collect();

    if conflicts.is_empty() {
        Ok(())
    } else {
        Err(conflicts)
    }
}
