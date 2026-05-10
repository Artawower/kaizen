use std::path::Path;

use anyhow::Result;
use dialoguer::{theme::ColorfulTheme, Confirm};
use owo_colors::OwoColorize;

use kaizen_core::ChezmoiClient;

use crate::output;

pub fn run(_engine: &kaizen_core::KaizenEngine, config_path: &Path, dry_run: bool) -> Result<()> {
    output::page_header(if dry_run {
        "uninstall  (dry-run)"
    } else {
        "uninstall"
    });

    let client = crate::chezmoi::StdChezmoiClient;
    let chezmoi_source = client.source_root().unwrap_or(None);
    let managed = client.managed_files().unwrap_or_default();
    let modified = client.locally_modified_files().unwrap_or_default();

    // When ~/.local/share/chezmoi is a symlink show the symlink path in the
    // plan, not the resolved target — that is what will actually be removed.
    // Show the symlink path in the plan when applicable so the user
    // sees what will actually be removed, not the resolved target.
    let chezmoi_display = chezmoi_source
        .as_deref()
        .map(|p| chezmoi_source_symlink(p).unwrap_or_else(|| p.to_owned()));

    print_plan(config_path, chezmoi_display.as_deref(), &managed, &modified);

    if dry_run {
        println!();
        println!("  Run without --dry-run to apply.");
        return Ok(());
    }

    if !modified.is_empty() {
        println!();
        output::item_warn("The following files were modified after kaizen applied them.");
        output::item_warn("These local changes will be lost:");
        println!();
        for f in &modified {
            println!("  {}  {}", "!".red(), f.display());
        }
        println!();
        let proceed = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt("Delete modified files anyway?")
            .default(false)
            .interact()?;
        if !proceed {
            println!("  Aborted.");
            return Ok(());
        }
    }

    let confirmed = Confirm::with_theme(&ColorfulTheme::default())
        .with_prompt("Proceed with uninstall?")
        .default(false)
        .interact()?;
    if !confirmed {
        println!("  Aborted.");
        return Ok(());
    }

    remove_dotfiles(&managed)?;
    remove_config(config_path)?;
    remove_chezmoi_source(chezmoi_source.as_deref())?;
    remove_binary();

    if which::which("nix").is_ok() {
        println!();
        output::item_warn(
            "Nix is installed but kaizen does not remove it automatically —              it is a system-level dependency outside kaizen's scope.",
        );
        output::item_warn(
            "To remove Nix manually:              https://docs.determinate.systems/determinate-nix/#uninstalling",
        );
    }

    println!();
    output::item_ok("kaizen uninstalled");
    Ok(())
}

fn remove_binary() {
    let exe = match std::env::current_exe() {
        Ok(p) => p,
        Err(_) => return,
    };
    match std::fs::remove_file(&exe) {
        Ok(()) => output::item_ok(&format!("removed {}", exe.display())),
        Err(e) if e.kind() == std::io::ErrorKind::PermissionDenied => {
            output::item_warn(&format!(
                "cannot remove {} — run: sudo rm {}",
                exe.display(),
                exe.display()
            ));
        }
        Err(_) => {}
    }
}

fn print_plan(
    config_path: &Path,
    chezmoi_source: Option<&Path>,
    managed: &[std::path::PathBuf],
    modified: &[std::path::PathBuf],
) {
    output::header("will remove");

    print_entry(config_path);

    if let Some(source) = chezmoi_source {
        print_entry(source);
    }

    if let Ok(exe) = std::env::current_exe() {
        print_entry(&exe);
    }

    if !managed.is_empty() {
        println!();
        output::header(&format!("dotfiles in ~ ({})", managed.len()));
        for f in managed.iter().take(10) {
            println!("  {}  {}", "→".dimmed(), f.display().to_string().dimmed());
        }
        if managed.len() > 10 {
            println!("  {}  ... and {} more", "→".dimmed(), managed.len() - 10);
        }
    }

    if !modified.is_empty() {
        println!();
        println!(
            "  {}  {} file(s) have local modifications — will warn before deletion",
            "!".yellow(),
            modified.len()
        );
    }
}

fn print_entry(path: &Path) {
    if path.exists() {
        println!(
            "  {}  {}",
            "→".dimmed(),
            path.display().to_string().dimmed()
        );
    } else {
        println!(
            "  {}  {} (not found)",
            "·".dimmed(),
            path.display().to_string().dimmed()
        );
    }
}

fn remove_dotfiles(files: &[std::path::PathBuf]) -> Result<()> {
    if files.is_empty() {
        return Ok(());
    }
    let client = crate::chezmoi::StdChezmoiClient;
    let report = client.remove_files(files, false)?;
    for f in &report.removed {
        output::item_ok(&format!("removed {}", f.display()));
    }
    if !report.skipped.is_empty() {
        output::item_warn(&format!("{} file(s) already gone", report.skipped.len()));
    }
    Ok(())
}

fn remove_config(path: &Path) -> Result<()> {
    if path.exists() {
        std::fs::remove_file(path)?;
        output::item_ok(&format!("removed {}", path.display()));
    }
    Ok(())
}

/// XDG path chezmoi always uses as its source root, regardless of platform.
/// `dirs::data_local_dir()` returns `~/Library/Application Support` on macOS
/// which is wrong — chezmoi follows XDG and uses `~/.local/share/chezmoi`.
/// Returns `Some(path)` if `path` is a symlink, `None` otherwise.
fn as_symlink(path: &Path) -> Option<std::path::PathBuf> {
    path.symlink_metadata()
        .ok()
        .filter(|m| m.file_type().is_symlink())
        .map(|_| path.to_owned())
}

/// XDG default chezmoi source dir: `~/.local/share/chezmoi`.
/// `dirs::data_local_dir()` returns `~/Library/Application Support` on macOS —
/// wrong. We derive the path from HOME directly.
fn default_chezmoi_dir() -> Option<std::path::PathBuf> {
    dirs::home_dir().map(|h| h.join(".local/share/chezmoi"))
}

/// If the chezmoi source is a symlink, returns the symlink path.
/// Checks the XDG default dir first, then the resolved source path,
/// so both standard and custom `sourceDir` setups are covered.
fn chezmoi_source_symlink(resolved: &Path) -> Option<std::path::PathBuf> {
    default_chezmoi_dir()
        .as_deref()
        .and_then(as_symlink)
        .or_else(|| as_symlink(resolved))
}

fn remove_chezmoi_source(source: Option<&Path>) -> Result<()> {
    let Some(p) = source else { return Ok(()) };

    // If the chezmoi source dir is a symlink, its target is the user's working
    // repository — remove only the symlink, never the real directory.
    if let Some(link) = chezmoi_source_symlink(p) {
        std::fs::remove_file(&link)?;
        output::item_ok(&format!("removed symlink {}", link.display()));
        return Ok(());
    }

    guard_against_dangerous_removal(p)?;
    if p.exists() {
        std::fs::remove_dir_all(p)?;
        output::item_ok(&format!("removed {}", p.display()));
    }
    Ok(())
}

/// Refuse to `remove_dir_all` obviously dangerous paths like `$HOME` or `/`.
/// This guards against `git_root()` accidentally returning an ancestor repo
/// (e.g. when `$HOME` is itself a git repository).
fn guard_against_dangerous_removal(path: &Path) -> Result<()> {
    // Filesystem root.
    if path.parent().is_none() {
        anyhow::bail!(
            "refusing to remove '{}' — looks like filesystem root",
            path.display()
        );
    }

    let home = dirs::home_dir();

    // Home directory itself.
    if let Some(ref h) = home {
        if path == h || path.canonicalize().ok().as_deref() == Some(h.as_path()) {
            anyhow::bail!(
                "refusing to remove '{}' — this is your home directory",
                path.display()
            );
        }
    }

    // Must be inside $HOME.
    if let Some(ref h) = home {
        if !path.starts_with(h) {
            anyhow::bail!(
                "refusing to remove '{}' — chezmoi source should be inside $HOME",
                path.display()
            );
        }
    }

    // If the path exists on disk it must be a git repository.
    // This catches cases where git_root() fell back to a non-chezmoi
    // ancestor (e.g. ~/.local/share when the actual repo was deleted).
    if path.exists() && !path.join(".git").exists() {
        anyhow::bail!(
            "refusing to remove '{}' — not a git repository \
             (chezmoi source should be a git clone; run `chezmoi source-path` to verify)",
            path.display()
        );
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    fn fixture_engine() -> kaizen_core::KaizenEngine {
        let features = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/features");
        kaizen_core::KaizenEngine::new(
            features,
            std::sync::Arc::new(crate::filesystem::StdFileSystem),
        )
    }

    fn temp_config() -> (tempfile::TempDir, PathBuf) {
        let dir = tempfile::tempdir().unwrap();
        let config = dir.path().join("config.toml");
        std::fs::write(&config, "schema_version = 1\n").unwrap();
        (dir, config)
    }

    #[test]
    fn guard_rejects_home_dir() {
        let home = dirs::home_dir().expect("home dir must exist in test");
        let err = guard_against_dangerous_removal(&home).unwrap_err();
        assert!(err.to_string().contains("home directory"), "{err}");
    }

    #[test]
    fn guard_rejects_filesystem_root() {
        let err = guard_against_dangerous_removal(std::path::Path::new("/")).unwrap_err();
        assert!(err.to_string().contains("filesystem root"), "{err}");
    }

    #[test]
    fn guard_rejects_path_outside_home() {
        let err = guard_against_dangerous_removal(std::path::Path::new("/etc")).unwrap_err();
        assert!(err.to_string().contains("inside $HOME"), "{err}");
    }

    #[test]
    fn guard_accepts_valid_chezmoi_source() {
        let home = dirs::home_dir().expect("home dir must exist in test");
        let chezmoi_source = home.join(".local/share/chezmoi");
        // Guard should pass (not bail) for a normal chezmoi source path.
        assert!(guard_against_dangerous_removal(&chezmoi_source).is_ok());
    }

    #[test]
    fn dry_run_does_not_remove_config() {
        let (_dir, config) = temp_config();
        run(&fixture_engine(), &config, true).unwrap();
        assert!(config.exists(), "dry-run must not delete config");
    }

    #[test]
    fn dry_run_does_not_remove_managed_files() {
        let dir = tempfile::tempdir().unwrap();
        let managed_file = dir.path().join("helix_config.toml");
        std::fs::write(&managed_file, "# helix").unwrap();

        let report = crate::chezmoi::StdChezmoiClient
            .remove_files(std::slice::from_ref(&managed_file), true)
            .unwrap();

        assert!(managed_file.exists(), "dry-run must not touch file");
        assert!(report.removed.contains(&managed_file));
    }
}
