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
    let chezmoi_source = client.source_path().unwrap_or(None);
    let managed = client.managed_files().unwrap_or_default();
    let modified = client.locally_modified_files().unwrap_or_default();
    let nix_installed = which::which("nix").is_ok();

    print_plan(
        config_path,
        chezmoi_source.as_deref(),
        &managed,
        &modified,
        nix_installed,
    );

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
    nix_installed: bool,
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

    if nix_installed {
        println!();
        println!("  {}  Nix (will ask for confirmation)", "?".yellow());
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
    if p.exists() {
        std::fs::remove_dir_all(p)?;
        output::item_ok(&format!("removed {}", p.display()));
    }
    Ok(())
}

fn uninstall_nix() -> Result<()> {
    let determinate = Path::new("/nix/nix-installer");
    let status = if determinate.exists() {
        output::item("running Determinate Systems nix-installer uninstall...");
        Command::new(determinate).arg("uninstall").status()?
    } else {
        output::item("running Nix uninstall...");
        Command::new("sh")
            .args([
                "-c",
                "/nix/nix-installer uninstall || \
                 (curl -sSfL https://install.determinate.systems/nix | sh -s -- uninstall)",
            ])
            .status()?
    };
    if !status.success() {
        anyhow::bail!(
            "Nix uninstall failed — remove manually: \
             https://nixos.org/manual/nix/stable/#sect-macos-installation"
        );
    }
    output::item_ok("Nix removed");
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
