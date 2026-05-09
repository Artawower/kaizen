use std::path::{Path, PathBuf};

use indexmap::IndexMap;
use serde::Serialize;

use crate::{ConfigPlan, KaizenError};

// ── Data types ───────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FileStatus {
    Modified,
    Deleted,
}

#[derive(Debug, Clone)]
pub struct ModifiedFile {
    pub path: PathBuf,
    pub status: FileStatus,
}

#[derive(Debug, Clone, Default)]
pub struct RemoveFilesReport {
    pub removed: Vec<PathBuf>,
    pub skipped: Vec<PathBuf>,
}

// ── Pure parsing ─────────────────────────────────────────────────────────────

/// Parse `chezmoi managed --include=files --path-style=absolute` output.
/// Handles both absolute and HOME-relative paths.
pub fn parse_managed_files(raw: &str, home: &Path) -> Vec<PathBuf> {
    raw.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(|l| {
            let p = Path::new(l);
            if p.is_absolute() {
                p.to_path_buf()
            } else {
                home.join(l)
            }
        })
        .collect()
}

/// Parse `chezmoi status` output into locally-modified file list.
pub fn parse_status_output(raw: &str, home: &Path) -> Vec<ModifiedFile> {
    raw.lines()
        .filter_map(|line| {
            if line.len() < 3 {
                return None;
            }
            let status_char = line.chars().next()?;
            let path_str = line[3..].trim();
            let status = match status_char {
                'M' => FileStatus::Modified,
                'D' => FileStatus::Deleted,
                _ => return None,
            };
            let path = if Path::new(path_str).is_absolute() {
                PathBuf::from(path_str)
            } else {
                home.join(path_str)
            };
            Some(ModifiedFile { path, status })
        })
        .collect()
}

/// Parse the raw stdout of `chezmoi source-path` into a PathBuf.
/// Handles both quoted and unquoted output, trims whitespace.
/// Returns None for empty or whitespace-only output.
pub fn parse_source_path_output(raw: &str) -> Option<PathBuf> {
    let s = raw.trim().trim_matches('"').trim();
    if s.is_empty() {
        return None;
    }
    Some(PathBuf::from(s))
}

// ── Pure chezmoidata generation and merge ────────────────────────────────────

#[derive(Serialize)]
struct ChezmoidataFile<'a> {
    layout: &'a str,
    features: &'a IndexMap<String, bool>,
}

/// Generate chezmoidata content from scratch (used in tests and first-time setup).
pub fn generate_chezmoidata(plan: &ConfigPlan) -> Result<String, KaizenError> {
    let layout = plan.settings.layout.as_deref().unwrap_or("qwerty");
    let data = ChezmoidataFile {
        layout,
        features: &plan.features_data,
    };
    Ok(toml::to_string_pretty(&data)?)
}

/// Merge kaizen-managed keys into an existing chezmoidata file (using real filesystem).
pub fn merge_chezmoidata(existing_path: &Path, plan: &ConfigPlan) -> Result<String, KaizenError> {
    merge_chezmoidata_with(existing_path, plan, &crate::StdFileSystem)
}

/// Merge kaizen-managed keys into an existing chezmoidata using an injected FileSystem.
///
/// Preserves all other keys (username, hostname, email, models, etc.) that
/// are maintained outside of kaizen. If the file does not exist, behaves
/// identically to `generate_chezmoidata`.
pub fn merge_chezmoidata_with(
    existing_path: &Path,
    plan: &ConfigPlan,
    fs: &dyn crate::FileSystem,
) -> Result<String, KaizenError> {
    let layout = plan.settings.layout.as_deref().unwrap_or("qwerty");

    let mut table: toml::map::Map<String, toml::Value> = if fs.exists(existing_path) {
        let raw = fs.read_to_string(existing_path)?;
        match toml::from_str::<toml::Value>(&raw) {
            Ok(toml::Value::Table(t)) => t,
            _ => toml::map::Map::new(),
        }
    } else {
        toml::map::Map::new()
    };

    table.insert("layout".to_owned(), toml::Value::String(layout.to_owned()));

    // Start with existing feature values so unknown features (e.g. "vcs") are
    // preserved. Kaizen-managed features are then overlaid on top.
    let mut features: toml::map::Map<String, toml::Value> = table
        .get("features")
        .and_then(|v| v.as_table())
        .cloned()
        .unwrap_or_default();
    for (k, v) in &plan.features_data {
        features.insert(k.clone(), toml::Value::Boolean(*v));
    }
    table.insert("features".to_owned(), toml::Value::Table(features));

    Ok(toml::to_string_pretty(&toml::Value::Table(table))?)
}

// ── Remote URL comparison ────────────────────────────────────────────────────

pub fn remotes_match(a: &str, b: &str) -> bool {
    normalize_remote(a) == normalize_remote(b)
}

fn normalize_remote(url: &str) -> String {
    let url = url.trim();
    let without_scheme = if let Some(rest) = url.strip_prefix("git@") {
        rest.replacen(':', "/", 1)
    } else if let Some(rest) = url.strip_prefix("https://") {
        rest.to_owned()
    } else if let Some(rest) = url.strip_prefix("http://") {
        rest.to_owned()
    } else {
        url.to_owned()
    };
    without_scheme
        .trim_end_matches(".git")
        .trim_end_matches('/')
        .to_lowercase()
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use std::path::{Path, PathBuf};

    use crate::{fs::mem::MemFileSystem, ConfigPlan, UserSettings};

    use super::{
        generate_chezmoidata, merge_chezmoidata_with, parse_managed_files,
        parse_source_path_output, parse_status_output, FileStatus,
    };

    fn make_plan(features: &[(&str, bool)], layout: Option<&str>) -> ConfigPlan {
        ConfigPlan {
            backend: "chezmoi".to_owned(),
            dotfiles_source: None,
            features_data: features.iter().map(|(k, v)| (k.to_string(), *v)).collect(),
            settings: UserSettings {
                layout: layout.map(str::to_owned),
            },
        }
    }

    // ── generate ─────────────────────────────────────────────────────────────

    #[test]
    fn generates_features_and_layout() {
        let plan = make_plan(&[("core", true), ("emacs", false)], Some("colemak"));
        let toml = generate_chezmoidata(&plan).unwrap();
        assert!(toml.contains("core = true"));
        assert!(toml.contains("emacs = false"));
        assert!(toml.contains("layout = \"colemak\""));
    }

    #[test]
    fn defaults_layout_to_qwerty_when_unset() {
        let plan = make_plan(&[], None);
        let toml = generate_chezmoidata(&plan).unwrap();
        assert!(toml.contains("layout = \"qwerty\""));
    }

    #[test]
    fn empty_features_produces_valid_toml() {
        let plan = make_plan(&[], Some("colemak"));
        let toml = generate_chezmoidata(&plan).unwrap();
        let _: toml::Value = toml::from_str(&toml).expect("must be valid toml");
    }

    // ── merge — uses MemFileSystem (no disk I/O) ──────────────────────────────

    fn mem_fs_with(path: &Path, content: &str) -> MemFileSystem {
        let fs = MemFileSystem::new();
        fs.add_file(path, content.as_bytes());
        fs
    }

    #[test]
    fn merge_preserves_unknown_keys() {
        let path = PathBuf::from("/tmp/.chezmoidata.toml");
        let fs = mem_fs_with(
            &path,
            "username = \"alice\"\nhostname = \"macbook\"\n\n[models]\ndefault = \"gpt-4\"\n\n[features]\ncore = true\n",
        );
        let plan = make_plan(&[("frontend", true)], Some("qwerty"));
        let merged = merge_chezmoidata_with(&path, &plan, &fs).unwrap();
        assert!(merged.contains("username = \"alice\""));
        assert!(merged.contains("hostname = \"macbook\""));
        assert!(merged.contains("default = \"gpt-4\""));
        assert!(merged.contains("frontend = true"));
        assert!(merged.contains("layout = \"qwerty\""));
    }

    #[test]
    fn merge_preserves_unknown_feature_keys() {
        let path = PathBuf::from("/tmp/.chezmoidata.toml");
        let fs = mem_fs_with(&path, "layout = \"colemak\"\n\n[features]\ncore = true\nvcs = true\n");
        let plan = make_plan(&[("core", true), ("frontend", false)], Some("colemak"));
        let merged = merge_chezmoidata_with(&path, &plan, &fs).unwrap();
        assert!(merged.contains("vcs = true"), "vcs must be preserved: {merged}");
        assert!(merged.contains("frontend = false"));
    }

    #[test]
    fn merge_updates_layout_without_touching_rest() {
        let path = PathBuf::from("/tmp/.chezmoidata.toml");
        let fs = mem_fs_with(
            &path,
            "layout = \"colemak\"\nusername = \"bob\"\n\n[features]\ncore = true\n",
        );
        let plan = make_plan(&[("core", true)], Some("qwerty"));
        let merged = merge_chezmoidata_with(&path, &plan, &fs).unwrap();
        assert!(merged.contains("layout = \"qwerty\""));
        assert!(merged.contains("username = \"bob\""));
    }

    #[test]
    fn merge_on_nonexistent_file_equals_generate() {
        let path = PathBuf::from("/tmp/nonexistent.toml");
        let fs = MemFileSystem::new(); // file not added → doesn't exist
        let plan = make_plan(&[("core", true)], Some("colemak"));
        let merged = merge_chezmoidata_with(&path, &plan, &fs).unwrap();
        let generated = generate_chezmoidata(&plan).unwrap();
        let merged_val: toml::Value = toml::from_str(&merged).unwrap();
        let gen_val: toml::Value = toml::from_str(&generated).unwrap();
        assert_eq!(merged_val, gen_val);
    }

    // ── parse ─────────────────────────────────────────────────────────────────

    #[test]
    fn parse_plain_path() {
        let p = parse_source_path_output("/Users/alice/.local/share/chezmoi\n").unwrap();
        assert_eq!(p.to_str().unwrap(), "/Users/alice/.local/share/chezmoi");
    }

    #[test]
    fn parse_quoted_path() {
        let p = parse_source_path_output("\"/Users/alice/.local/share/chezmoi\"\n").unwrap();
        assert_eq!(p.to_str().unwrap(), "/Users/alice/.local/share/chezmoi");
    }

    #[test]
    fn parse_empty_returns_none() {
        assert!(parse_source_path_output("").is_none());
        assert!(parse_source_path_output("   \n").is_none());
        assert!(parse_source_path_output("\"\"").is_none());
    }

    #[test]
    fn parse_path_with_spaces_in_name() {
        let p = parse_source_path_output("/Users/alice/my dotfiles\n").unwrap();
        assert_eq!(p.to_str().unwrap(), "/Users/alice/my dotfiles");
    }

    #[test]
    fn managed_files_absolute_paths() {
        let home = Path::new("/home/alice");
        let raw = "/home/alice/.config/helix/config.toml\n/home/alice/.config/zellij/config.kdl\n";
        let files = parse_managed_files(raw, home);
        assert_eq!(files.len(), 2);
        assert_eq!(files[0], PathBuf::from("/home/alice/.config/helix/config.toml"));
        assert_eq!(files[1], PathBuf::from("/home/alice/.config/zellij/config.kdl"));
    }

    #[test]
    fn managed_files_relative_paths_joined_with_home() {
        let home = Path::new("/home/alice");
        let raw = ".config/helix/config.toml\n.config/niri/config.kdl\n";
        let files = parse_managed_files(raw, home);
        assert_eq!(files[0], PathBuf::from("/home/alice/.config/helix/config.toml"));
        assert_eq!(files[1], PathBuf::from("/home/alice/.config/niri/config.kdl"));
    }

    #[test]
    fn managed_files_empty_output() {
        assert!(parse_managed_files("", Path::new("/home/alice")).is_empty());
    }

    #[test]
    fn managed_files_skips_blank_lines() {
        let raw = "/home/alice/.config/a.toml\n\n   \n/home/alice/.config/b.toml\n";
        assert_eq!(parse_managed_files(raw, Path::new("/home/alice")).len(), 2);
    }

    #[test]
    fn status_parses_modified_files() {
        let home = Path::new("/home/alice");
        let raw = "M  .config/helix/config.toml\nM  .config/mise.toml\n";
        let modified = parse_status_output(raw, home);
        assert_eq!(modified.len(), 2);
        assert_eq!(modified[0].status, FileStatus::Modified);
        assert_eq!(modified[0].path, PathBuf::from("/home/alice/.config/helix/config.toml"));
    }

    #[test]
    fn status_ignores_non_modified_lines() {
        let home = Path::new("/home/alice");
        let raw = "M  .config/helix/config.toml\nA  .config/new.toml\n";
        let result = parse_status_output(raw, home);
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].status, FileStatus::Modified);
    }

    #[test]
    fn status_empty_output_returns_empty() {
        assert!(parse_status_output("", Path::new("/home/alice")).is_empty());
    }

    // ── remotes ───────────────────────────────────────────────────────────────

    use super::remotes_match;

    #[test]
    fn ssh_and_https_remotes_match() {
        assert!(remotes_match(
            "git@github.com:user/dots.git",
            "https://github.com/user/dots"
        ));
    }

    #[test]
    fn same_ssh_remotes_match() {
        assert!(remotes_match(
            "git@github.com:user/dots.git",
            "git@github.com:user/dots.git"
        ));
    }

    #[test]
    fn different_remotes_do_not_match() {
        assert!(!remotes_match(
            "git@github.com:user/dots.git",
            "git@github.com:other/dots.git"
        ));
    }

}
