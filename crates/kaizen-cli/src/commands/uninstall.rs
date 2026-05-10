use std::path::Path;
use std::process::Command;

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
    let nix_installed = which::which("nix").is_ok();

    print_plan(config_path, chezmoi_source.as_deref(), &managed, &modified);

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

    if nix_installed {
        println!();
        let remove_nix = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt(
                "Remove Nix? This will delete ALL Nix packages and home-manager. Are you sure?",
            )
            .default(false)
            .interact()?;
        if remove_nix {
            uninstall_nix()?;
        } else {
            output::item_ok("Nix kept — your packages remain installed");
        }
    }

    println!();
    output::item_ok("kaizen uninstalled");
    Ok(())
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

fn remove_chezmoi_source(source: Option<&Path>) -> Result<()> {
    let Some(p) = source else { return Ok(()) };
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

fn uninstall_nix() -> Result<()> {
    // Try uninstallers in order of reliability.
    // IMPORTANT: do NOT download a fresh Determinate installer and run
    // `uninstall` — it requires a receipt from the original install and
    // will always fail without one.
    let attempts: &[(&str, &[&str])] = &[
        // 1. Determinate Systems installer binary (placed by the installer)
        ("/nix/nix-installer", &["uninstall"]),
        // 2. Determinate Systems installer if it ended up in PATH
        ("nix-installer", &["uninstall"]),

    ];

    for (cmd, args) in attempts {
        let available = if cmd.starts_with('/') {
            Path::new(cmd).exists()
        } else {
            which::which(cmd).is_ok()
        };
        if !available {
            continue;
        }
        output::item(&format!("running {cmd} uninstall…"));
        let status = Command::new(cmd).args(*args).status()?;
        if status.success() {
            output::item_ok("Nix removed");
            return Ok(());
        }
        output::item_warn(&format!("{cmd} uninstall failed, trying next method…"));
    }

    anyhow::bail!(
        "could not uninstall Nix automatically.\n\
         \n\
         Determinate Nix: https://docs.determinate.systems/determinate-nix/#uninstalling\n\
         Official Nix:    https://nixos.org/manual/nix/stable/#sect-macos-installation"
    );
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
