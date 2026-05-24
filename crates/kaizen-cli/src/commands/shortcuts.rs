use std::collections::BTreeMap;
use std::path::Path;

use anyhow::{Context, Result};
use kaizen_core::{ShortcutCatalog, ShortcutDefinition};
use owo_colors::OwoColorize;

use crate::output;

pub fn run(
    only: &[String],
    all_layouts: bool,
    json: bool,
    catalog_path: &Path,
    layout: Option<&str>,
) -> Result<()> {
    if all_layouts {
        return run_all_layouts(only, catalog_path);
    }

    let catalog = ShortcutCatalog::load(catalog_path, layout)
        .with_context(|| format!("failed to load {}", catalog_path.display()))?;

    let shortcuts: Vec<&ShortcutDefinition> = catalog.by_prefix(only).collect();

    if shortcuts.is_empty() {
        output::item_warn("no shortcuts matched");
        return Ok(());
    }

    if json {
        print_json(&shortcuts);
        return Ok(());
    }

    print_grouped(&shortcuts);
    Ok(())
}

fn run_all_layouts(only: &[String], catalog_path: &Path) -> Result<()> {
    let layouts = ShortcutCatalog::all_layouts(catalog_path)
        .with_context(|| format!("failed to load {}", catalog_path.display()))?;

    let base = layouts.get("base").cloned().unwrap_or_default();
    let other_layouts: Vec<&str> = layouts
        .keys()
        .filter(|k| k.as_str() != "base")
        .map(String::as_str)
        .collect();

    let catalog = ShortcutCatalog::load(catalog_path, None)?;
    let shortcuts: Vec<&ShortcutDefinition> = catalog.by_prefix(only).collect();

    if shortcuts.is_empty() {
        output::item_warn("no shortcuts matched");
        return Ok(());
    }

    let max_id = shortcuts.iter().map(|s| s.id.len()).max().unwrap_or(0);

    for s in &shortcuts {
        let base_keys = base
            .get(&s.id)
            .map(|k| k.join(""))
            .unwrap_or_else(|| s.keys.join(""));

        let mut parts = vec![format!("base: {base_keys}")];
        for layout_name in &other_layouts {
            if let Some(keys) = layouts.get(*layout_name).and_then(|m| m.get(&s.id)) {
                parts.push(format!("{layout_name}: {}", keys.join("")));
            }
        }

        let desc = s.description.as_deref().unwrap_or("");
        println!(
            "  {:<width$}  {}  {}",
            s.id,
            parts.join("   "),
            desc.dimmed(),
            width = max_id,
        );
    }

    Ok(())
}

fn print_grouped(shortcuts: &[&ShortcutDefinition]) {
    let mut groups: BTreeMap<&str, Vec<&ShortcutDefinition>> = BTreeMap::new();
    for s in shortcuts {
        let group = s.group.as_deref().unwrap_or("Other");
        groups.entry(group).or_default().push(s);
    }

    let max_id = shortcuts.iter().map(|s| s.id.len()).max().unwrap_or(0);
    let max_keys = shortcuts
        .iter()
        .map(|s| s.keys.join("").len())
        .max()
        .unwrap_or(0);

    let mut first = true;
    for (group, entries) in &groups {
        if !first {
            println!();
        }
        first = false;
        println!("{}", group.bold());
        for s in entries {
            let keys_str = s.keys.join("");
            let desc = s.description.as_deref().unwrap_or("");
            println!(
                "  {:<id_w$}  {:<keys_w$}  {}",
                s.id,
                keys_str,
                desc.dimmed(),
                id_w = max_id,
                keys_w = max_keys,
            );
        }
    }
}

fn print_json(shortcuts: &[&ShortcutDefinition]) {
    let values: Vec<serde_json::Value> = shortcuts
        .iter()
        .map(|s| {
            serde_json::json!({
                "id": s.id,
                "keys": s.keys,
                "group": s.group,
                "description": s.description,
            })
        })
        .collect();
    println!(
        "{}",
        serde_json::to_string_pretty(&values).unwrap_or_default()
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write_catalog(dir: &std::path::Path, content: &str) -> std::path::PathBuf {
        let path = dir.join("keybindings.toml");
        std::fs::write(&path, content).unwrap();
        path
    }

    const FIXTURE: &str = r#"
[shortcuts]
"nav.down"  = { keys = ["j"], group = "Navigation", description = "Move focus down" }
"nav.up"    = { keys = ["k"], group = "Navigation", description = "Move focus up" }
"vcs.ui"    = { keys = ["g", "g"], group = "VCS", description = "Open VCS UI" }

[layout.colemak.shortcuts]
"nav.down" = ["n"]
"nav.up"   = ["e"]
"#;

    #[test]
    fn dry_run_shows_grouped_output() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_catalog(dir.path(), FIXTURE);
        // Must succeed without error — visual output not captured here.
        run(&[], false, false, &path, None).unwrap();
    }

    #[test]
    fn only_filter_shows_subset() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_catalog(dir.path(), FIXTURE);
        let catalog = kaizen_core::ShortcutCatalog::load(&path, None).unwrap();
        let prefixes = vec!["nav".to_string()];
        let nav: Vec<_> = catalog.by_prefix(&prefixes).collect();
        assert_eq!(nav.len(), 2, "only nav.* returned");
        assert!(nav.iter().all(|s| s.id.starts_with("nav")));
    }

    #[test]
    fn json_output_succeeds() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_catalog(dir.path(), FIXTURE);
        run(&[], false, true, &path, None).unwrap();
    }

    #[test]
    fn colemak_layout_applied() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_catalog(dir.path(), FIXTURE);
        let catalog = kaizen_core::ShortcutCatalog::load(&path, Some("colemak")).unwrap();
        let down = catalog
            .shortcuts
            .iter()
            .find(|s| s.id == "nav.down")
            .unwrap();
        assert_eq!(down.keys, vec!["n"]);
        assert_eq!(down.description.as_deref(), Some("Move focus down"));
    }
}
