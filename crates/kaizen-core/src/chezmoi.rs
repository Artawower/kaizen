use std::path::{Path, PathBuf};
use std::process::Command;

use indexmap::IndexMap;
use serde::Serialize;

use crate::{ConfigPlan, KaizenError};

// ── Dotfile removal ──────────────────────────────────────────────────────────

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

/// List all files deployed by chezmoi into `~`.
pub fn managed_files() -> Result<Vec<PathBuf>, KaizenError> {
    let home = dirs::home_dir().ok_or(KaizenError::HomeDirUnavailable)?;
    let out = Command::new("chezmoi")
        .args(["managed", "--include=files", "--path-style=absolute"])
        .output()?;
    if !out.status.success() {
        return Ok(vec![]);
    }
    Ok(parse_managed_files(
        &String::from_utf8_lossy(&out.stdout),
        &home,
    ))
}

/// List files that were modified locally after chezmoi apply.
pub fn locally_modified_files() -> Result<Vec<PathBuf>, KaizenError> {
    let home = dirs::home_dir().ok_or(KaizenError::HomeDirUnavailable)?;
    let out = Command::new("chezmoi").arg("status").output()?;
    if !out.status.success() {
        return Ok(vec![]);
    }
    Ok(
        parse_status_output(&String::from_utf8_lossy(&out.stdout), &home)
            .into_iter()
            .filter(|f| f.status == FileStatus::Modified)
            .map(|f| f.path)
            .collect(),
    )
}

/// Remove files from the filesystem. Skips missing files.
/// `dry_run = true` collects the plan without touching the disk.
pub fn remove_files(files: &[PathBuf], dry_run: bool) -> Result<RemoveFilesReport, KaizenError> {
    let mut report = RemoveFilesReport::default();
    for file in files {
        if !file.exists() {
            report.skipped.push(file.clone());
            continue;
        }
        if !dry_run {
            std::fs::remove_file(file).map_err(KaizenError::Io)?;
        }
        report.removed.push(file.clone());
    }
    Ok(report)
}

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

/// Merge kaizen-managed keys (layout, features) into an existing chezmoidata file.
///
/// Preserves all other keys (username, hostname, email, models, etc.) that
/// are maintained outside of kaizen. If the file does not exist, behaves
/// identically to `generate_chezmoidata`.
/// Merge kaizen-managed keys into an existing chezmoidata using real filesystem.
pub fn merge_chezmoidata(existing_path: &Path, plan: &ConfigPlan) -> Result<String, KaizenError> {
    merge_chezmoidata_with(existing_path, plan, &crate::StdFileSystem)
}

/// Merge kaizen-managed keys into an existing chezmoidata using an injected FileSystem.
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

pub fn current_remote(source_dir: &Path) -> Result<Option<String>, KaizenError> {
    let out = Command::new("git")
        .arg("-C")
        .arg(source_dir)
        .args(["remote", "get-url", "origin"])
        .output()?;
    if !out.status.success() {
        return Ok(None);
    }
    Ok(Some(String::from_utf8_lossy(&out.stdout).trim().to_owned()))
}

pub fn backup_source_dir(source_dir: &Path) -> Result<PathBuf, KaizenError> {
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let name = source_dir.file_name().unwrap_or_default().to_string_lossy();
    let backup = source_dir.with_file_name(format!("{name}.bak.{ts}"));
    std::fs::rename(source_dir, &backup)?;
    Ok(backup)
}

#[derive(Debug, Clone)]
pub enum SourcePathState {
    /// `chezmoi source-path` returned a valid path — chezmoi is initialized.
    Confirmed(PathBuf),
    /// `chezmoi source-path` ran but reported no source dir — chezmoi is not initialized.
    /// Carries the conventional default path where init would place the source.
    Uninitialized(PathBuf),
}

impl SourcePathState {
    pub fn path(&self) -> &Path {
        match self {
            SourcePathState::Confirmed(p) | SourcePathState::Uninitialized(p) => p,
        }
    }

    pub fn into_confirmed(self) -> Result<PathBuf, KaizenError> {
        match self {
            SourcePathState::Confirmed(p) => Ok(p),
            SourcePathState::Uninitialized(_) => Err(KaizenError::ChezmoidataTargetUnknown),
        }
    }
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

pub fn standalone_source_dir() -> Result<Option<PathBuf>, KaizenError> {
    let out = Command::new("chezmoi").arg("source-path").output()?;
    if !out.status.success() {
        return Ok(None);
    }
    let raw = String::from_utf8_lossy(&out.stdout);
    match parse_source_path_output(&raw) {
        Some(path) if path.exists() => Ok(Some(path)),
        _ => Ok(None),
    }
}

pub fn init_source(url: &str) -> Result<(), KaizenError> {
    let status = Command::new("chezmoi").args(["init", url]).status()?;
    if !status.success() {
        return Err(KaizenError::ChezmoidataInitFailed {
            url: url.to_owned(),
            code: status.code(),
        });
    }
    Ok(())
}

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

pub fn source_path(plan: &ConfigPlan) -> Result<SourcePathState, KaizenError> {
    if plan.backend != "chezmoi" {
        return Err(KaizenError::UnsupportedDotfilesBackend {
            backend: plan.backend.clone(),
        });
    }

    let out = Command::new("chezmoi").arg("source-path").output()?;

    if out.status.success() {
        let raw = String::from_utf8_lossy(&out.stdout);
        if let Some(path) = parse_source_path_output(&raw) {
            if path.exists() {
                return Ok(SourcePathState::Confirmed(path));
            }
            return Ok(SourcePathState::Uninitialized(path));
        }
    }

    let fallback = dirs::home_dir()
        .map(|h| h.join(".local/share/chezmoi"))
        .ok_or(KaizenError::ChezmoidataTargetUnknown)?;

    Ok(SourcePathState::Uninitialized(fallback))
}

#[cfg(test)]
mod tests {
    use indexmap::IndexMap;

    use crate::{ConfigPlan, UserSettings};

    use super::{generate_chezmoidata, merge_chezmoidata, parse_source_path_output};

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
        assert!(!toml.is_empty());
        let _: toml::Value = toml::from_str(&toml).expect("must be valid toml");
    }

    #[test]
    fn merge_preserves_unknown_keys() {
        let existing = "username = \"alice\"\nhostname = \"macbook\"\n\n[models]\ndefault = \"gpt-4\"\n\n[features]\ncore = true\n";
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(".chezmoidata.toml");
        std::fs::write(&path, existing).unwrap();

        let plan = make_plan(&[("frontend", true)], Some("qwerty"));
        let merged = merge_chezmoidata(&path, &plan).unwrap();

        assert!(
            merged.contains("username = \"alice\""),
            "must preserve username"
        );
        assert!(
            merged.contains("hostname = \"macbook\""),
            "must preserve hostname"
        );
        assert!(
            merged.contains("default = \"gpt-4\""),
            "must preserve models"
        );
        assert!(merged.contains("frontend = true"), "must update features");
        assert!(merged.contains("layout = \"qwerty\""), "must update layout");
    }

    #[test]
    fn merge_preserves_unknown_feature_keys() {
        let existing = "layout = \"colemak\"\n\n[features]\ncore = true\nvcs = true\n";
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(".chezmoidata.toml");
        std::fs::write(&path, existing).unwrap();

        // kaizen config does not know about 'vcs'
        let plan = make_plan(&[("core", true), ("frontend", false)], Some("colemak"));
        let merged = merge_chezmoidata(&path, &plan).unwrap();

        assert!(
            merged.contains("vcs = true"),
            "unknown feature 'vcs' must be preserved: {merged}"
        );
        assert!(
            merged.contains("frontend = false"),
            "kaizen-managed feature must be updated"
        );
    }

    #[test]
    fn merge_updates_layout_without_touching_rest() {
        let existing = "layout = \"colemak\"\nusername = \"bob\"\n\n[features]\ncore = true\n";
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(".chezmoidata.toml");
        std::fs::write(&path, existing).unwrap();

        let plan = make_plan(&[("core", true)], Some("qwerty"));
        let merged = merge_chezmoidata(&path, &plan).unwrap();

        assert!(
            merged.contains("layout = \"qwerty\""),
            "layout must be updated"
        );
        assert!(
            merged.contains("username = \"bob\""),
            "username must be preserved"
        );
    }

    #[test]
    fn merge_on_nonexistent_file_equals_generate() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("nonexistent.toml");

        let plan = make_plan(&[("core", true)], Some("colemak"));
        let merged = merge_chezmoidata(&path, &plan).unwrap();
        let generated = generate_chezmoidata(&plan).unwrap();

        let merged_val: toml::Value = toml::from_str(&merged).unwrap();
        let gen_val: toml::Value = toml::from_str(&generated).unwrap();
        assert_eq!(merged_val, gen_val);
    }

    #[test]
    fn rejects_non_chezmoi_backend() {
        let plan = ConfigPlan {
            backend: "nix".to_owned(),
            dotfiles_source: None,
            features_data: IndexMap::new(),
            settings: UserSettings { layout: None },
        };
        assert!(super::source_path(&plan).is_err());
    }

    #[test]
    fn parse_plain_path() {
        let out = "/Users/alice/.local/share/chezmoi\n";
        let p = parse_source_path_output(out).unwrap();
        assert_eq!(p.to_str().unwrap(), "/Users/alice/.local/share/chezmoi");
    }

    #[test]
    fn parse_quoted_path() {
        let out = "\"/Users/alice/.local/share/chezmoi\"\n";
        let p = parse_source_path_output(out).unwrap();
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
        let out = "/Users/alice/my dotfiles\n";
        let p = parse_source_path_output(out).unwrap();
        assert_eq!(p.to_str().unwrap(), "/Users/alice/my dotfiles");
    }

    use super::{parse_managed_files, parse_status_output, remove_files, FileStatus};
    use std::path::{Path, PathBuf};

    #[test]
    fn managed_files_absolute_paths() {
        let home = Path::new("/home/alice");
        let raw = "/home/alice/.config/helix/config.toml\n/home/alice/.config/zellij/config.kdl\n";
        let files = parse_managed_files(raw, home);
        assert_eq!(files.len(), 2);
        assert_eq!(
            files[0],
            PathBuf::from("/home/alice/.config/helix/config.toml")
        );
        assert_eq!(
            files[1],
            PathBuf::from("/home/alice/.config/zellij/config.kdl")
        );
    }

    #[test]
    fn managed_files_relative_paths_joined_with_home() {
        let home = Path::new("/home/alice");
        let raw = ".config/helix/config.toml\n.config/niri/config.kdl\n";
        let files = parse_managed_files(raw, home);
        assert_eq!(
            files[0],
            PathBuf::from("/home/alice/.config/helix/config.toml")
        );
        assert_eq!(
            files[1],
            PathBuf::from("/home/alice/.config/niri/config.kdl")
        );
    }

    #[test]
    fn managed_files_empty_output() {
        let files = parse_managed_files("", Path::new("/home/alice"));
        assert!(files.is_empty());
    }

    #[test]
    fn managed_files_skips_blank_lines() {
        let raw = "/home/alice/.config/a.toml\n\n   \n/home/alice/.config/b.toml\n";
        let files = parse_managed_files(raw, Path::new("/home/alice"));
        assert_eq!(files.len(), 2);
    }

    #[test]
    fn status_parses_modified_files() {
        let home = Path::new("/home/alice");
        let raw = "M  .config/helix/config.toml\nM  .config/mise.toml\n";
        let modified = parse_status_output(raw, home);
        assert_eq!(modified.len(), 2);
        assert_eq!(modified[0].status, FileStatus::Modified);
        assert_eq!(
            modified[0].path,
            PathBuf::from("/home/alice/.config/helix/config.toml")
        );
    }

    #[test]
    fn status_ignores_non_modified_lines() {
        let home = Path::new("/home/alice");
        let raw = "M  .config/helix/config.toml\nA  .config/new.toml\n";
        let result = parse_status_output(raw, home);
        // A (added) is not in our set → ignored
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].status, FileStatus::Modified);
    }

    #[test]
    fn status_empty_output_returns_empty() {
        let result = parse_status_output("", Path::new("/home/alice"));
        assert!(result.is_empty());
    }

    #[test]
    fn remove_files_dry_run_does_not_delete() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("helix_config.toml");
        std::fs::write(&file, "# helix").unwrap();

        let report = remove_files(&[file.clone()], true).unwrap();

        assert!(file.exists(), "dry-run must not delete the file");
        assert_eq!(report.removed, vec![file]);
        assert!(report.skipped.is_empty());
    }

    #[test]
    fn remove_files_deletes_existing() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("config.toml");
        std::fs::write(&file, "data").unwrap();

        let report = remove_files(&[file.clone()], false).unwrap();

        assert!(!file.exists(), "file must be deleted");
        assert_eq!(report.removed, vec![file]);
        assert!(report.skipped.is_empty());
    }

    #[test]
    fn remove_files_skips_missing() {
        let dir = tempfile::tempdir().unwrap();
        let missing = dir.path().join("nonexistent.toml");

        let report = remove_files(&[missing.clone()], false).unwrap();

        assert!(report.removed.is_empty());
        assert_eq!(report.skipped, vec![missing]);
    }

    #[test]
    fn remove_files_mixed_existing_and_missing() {
        let dir = tempfile::tempdir().unwrap();
        let exists = dir.path().join("exists.toml");
        let missing = dir.path().join("missing.toml");
        std::fs::write(&exists, "data").unwrap();

        let report = remove_files(&[exists.clone(), missing.clone()], false).unwrap();

        assert_eq!(report.removed, vec![exists]);
        assert_eq!(report.skipped, vec![missing]);
    }
}
