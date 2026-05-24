use std::collections::BTreeMap;
use std::path::Path;

use anyhow::Result;

#[derive(Debug, Clone)]
pub struct ShortcutDefinition {
    pub id: String,
    pub keys: Vec<String>,
    pub group: Option<String>,
    pub description: Option<String>,
}

pub struct ShortcutCatalog {
    pub shortcuts: Vec<ShortcutDefinition>,
}

impl ShortcutCatalog {
    /// Load the catalog from `path`, applying the layout overlay when `layout` is set.
    pub fn load(path: &Path, layout: Option<&str>) -> Result<Self> {
        let content = std::fs::read_to_string(path)?;
        let doc: toml::Value = content.parse()?;

        let base = doc
            .get("shortcuts")
            .and_then(|v| v.as_table())
            .cloned()
            .unwrap_or_default();

        let overlay: BTreeMap<String, Vec<String>> = layout
            .and_then(|l| {
                doc.get("layout")?
                    .get(l)?
                    .get("shortcuts")?
                    .as_table()
                    .map(|t| {
                        t.iter()
                            .filter_map(|(k, v)| {
                                let keys = v
                                    .as_array()?
                                    .iter()
                                    .filter_map(|s| s.as_str().map(String::from))
                                    .collect();
                                Some((k.clone(), keys))
                            })
                            .collect()
                    })
            })
            .unwrap_or_default();

        let shortcuts = base
            .iter()
            .filter_map(|(id, val)| {
                let (base_keys, group, description) = match val {
                    toml::Value::Array(arr) => {
                        let keys = arr
                            .iter()
                            .filter_map(|v| v.as_str().map(String::from))
                            .collect();
                        (keys, None, None)
                    }
                    toml::Value::Table(t) => {
                        let keys = t
                            .get("keys")?
                            .as_array()?
                            .iter()
                            .filter_map(|v| v.as_str().map(String::from))
                            .collect();
                        let group = t.get("group").and_then(|v| v.as_str()).map(String::from);
                        let description = t
                            .get("description")
                            .and_then(|v| v.as_str())
                            .map(String::from);
                        (keys, group, description)
                    }
                    _ => return None,
                };

                let final_keys = overlay.get(id).cloned().unwrap_or(base_keys);

                Some(ShortcutDefinition {
                    id: id.clone(),
                    keys: final_keys,
                    group,
                    description,
                })
            })
            .collect();

        Ok(ShortcutCatalog { shortcuts })
    }

    /// Return shortcuts whose id starts with any of `prefixes`.
    /// Empty prefix list returns all shortcuts.
    pub fn by_prefix<'a>(
        &'a self,
        prefixes: &'a [String],
    ) -> impl Iterator<Item = &'a ShortcutDefinition> {
        self.shortcuts.iter().filter(move |s| {
            prefixes.is_empty() || prefixes.iter().any(|p| s.id.starts_with(p.as_str()))
        })
    }

    /// Return all layout-specific key mappings for every shortcut.
    ///
    /// Result: layout_name → id → resolved keys.
    /// The special key `"base"` holds the default (no-overlay) values.
    pub fn all_layouts(path: &Path) -> Result<BTreeMap<String, BTreeMap<String, Vec<String>>>> {
        let content = std::fs::read_to_string(path)?;
        let doc: toml::Value = content.parse()?;

        let mut result: BTreeMap<String, BTreeMap<String, Vec<String>>> = BTreeMap::new();

        if let Some(base) = doc.get("shortcuts").and_then(|v| v.as_table()) {
            for (id, val) in base {
                if let Some(keys) = extract_keys_from_value(val) {
                    result
                        .entry("base".into())
                        .or_default()
                        .insert(id.clone(), keys);
                }
            }
        }

        if let Some(layouts) = doc.get("layout").and_then(|v| v.as_table()) {
            for (layout_name, layout_val) in layouts {
                if let Some(shortcuts) = layout_val.get("shortcuts").and_then(|v| v.as_table()) {
                    for (id, val) in shortcuts {
                        if let Some(keys) = extract_keys_from_value(val) {
                            result
                                .entry(layout_name.clone())
                                .or_default()
                                .insert(id.clone(), keys);
                        }
                    }
                }
            }
        }

        Ok(result)
    }
}

fn extract_keys_from_value(val: &toml::Value) -> Option<Vec<String>> {
    match val {
        toml::Value::Array(arr) => Some(
            arr.iter()
                .filter_map(|v| v.as_str().map(String::from))
                .collect(),
        ),
        toml::Value::Table(t) => t.get("keys")?.as_array().map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(String::from))
                .collect()
        }),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write_catalog(dir: &std::path::Path, content: &str) -> std::path::PathBuf {
        let path = dir.join("keybindings.toml");
        std::fs::write(&path, content).unwrap();
        path
    }

    #[test]
    fn load_base_array_format() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_catalog(
            dir.path(),
            r#"
[shortcuts]
"vcs.ui" = ["g", "g"]
"nav.down" = ["j"]
"#,
        );
        let catalog = ShortcutCatalog::load(&path, None).unwrap();
        assert_eq!(catalog.shortcuts.len(), 2);
        let vcs = catalog.shortcuts.iter().find(|s| s.id == "vcs.ui").unwrap();
        assert_eq!(vcs.keys, vec!["g", "g"]);
    }

    #[test]
    fn load_object_format_extracts_keys_and_metadata() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_catalog(
            dir.path(),
            r#"
[shortcuts]
"nav.down" = { keys = ["j"], group = "Navigation", description = "Move focus down" }
"#,
        );
        let catalog = ShortcutCatalog::load(&path, None).unwrap();
        let def = &catalog.shortcuts[0];
        assert_eq!(def.keys, vec!["j"]);
        assert_eq!(def.group.as_deref(), Some("Navigation"));
        assert_eq!(def.description.as_deref(), Some("Move focus down"));
    }

    #[test]
    fn overlay_replaces_keys_keeps_description() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_catalog(
            dir.path(),
            r#"
[shortcuts]
"nav.down" = { keys = ["j"], group = "Navigation", description = "Move focus down" }

[layout.colemak.shortcuts]
"nav.down" = ["n"]
"#,
        );
        let catalog = ShortcutCatalog::load(&path, Some("colemak")).unwrap();
        let def = catalog
            .shortcuts
            .iter()
            .find(|s| s.id == "nav.down")
            .unwrap();
        assert_eq!(def.keys, vec!["n"], "overlay applied");
        assert_eq!(
            def.description.as_deref(),
            Some("Move focus down"),
            "description preserved from base"
        );
    }

    #[test]
    fn filter_by_prefix() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_catalog(
            dir.path(),
            r#"
[shortcuts]
"nav.down" = ["j"]
"nav.up"   = ["k"]
"vcs.ui"   = ["g", "g"]
"#,
        );
        let catalog = ShortcutCatalog::load(&path, None).unwrap();
        let prefixes = vec!["nav".to_string()];
        let nav: Vec<_> = catalog.by_prefix(&prefixes).collect();
        assert_eq!(nav.len(), 2, "only nav.* returned");
        assert!(nav.iter().all(|s| s.id.starts_with("nav")));
        let all: Vec<_> = catalog.by_prefix(&[]).collect();
        assert_eq!(all.len(), 3, "empty prefix returns all");
    }

    #[test]
    fn all_layouts_returns_base_and_overlays() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_catalog(
            dir.path(),
            r#"
[shortcuts]
"nav.down" = { keys = ["j"], group = "Navigation", description = "Move focus down" }

[layout.colemak.shortcuts]
"nav.down" = ["n"]
"#,
        );
        let layouts = ShortcutCatalog::all_layouts(&path).unwrap();
        assert_eq!(
            layouts["base"]["nav.down"],
            vec!["j"],
            "base must hold qwerty value"
        );
        assert_eq!(
            layouts["colemak"]["nav.down"],
            vec!["n"],
            "colemak overlay present"
        );
    }
}
