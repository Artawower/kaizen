use std::path::Path;
use std::process::Command;

use anyhow::Result;
use dialoguer::{theme::ColorfulTheme, Confirm};
use owo_colors::OwoColorize;

use crate::output;

pub fn run(_engine: &kaizen_core::KaizenEngine, config_path: &Path, dry_run: bool) -> Result<()> {
    output::page_header(if dry_run {
        "uninstall  (dry-run)"
    } else {
        "uninstall"
    });

    let chezmoi_source = kaizen_core::chezmoi::standalone_source_dir().unwrap_or(None);
    let chezmoi_data = chezmoi_source.as_ref().map(|s| s.join(".chezmoidata.toml"));
    let nix_installed = which::which("nix").is_ok();

    print_plan(config_path, chezmoi_source.as_deref(), nix_installed);

    if dry_run {
        println!();
        println!("  Run without --dry-run to apply.");
        return Ok(());
    }

    let confirmed = Confirm::with_theme(&ColorfulTheme::default())
        .with_prompt("Proceed with uninstall?")
        .default(false)
        .interact()?;

    if !confirmed {
        println!("  Aborted.");
        return Ok(());
    }

    remove_config(config_path)?;
    remove_chezmoidata(chezmoi_data.as_deref())?;
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
    output::item_warn("Config files in ~/.config/ remain — they are now plain files, not managed by kaizen.");
    println!();
    output::item_ok("kaizen uninstalled");
    Ok(())
}

fn print_plan(config_path: &Path, chezmoi_source: Option<&Path>, nix_installed: bool) {
    output::header("will remove");

    print_entry(config_path);

    if let Some(source) = chezmoi_source {
        print_entry(&source.join(".chezmoidata.toml"));
        print_entry(source);
    }

    if nix_installed {
        println!();
        println!("  {}  Nix (will ask for confirmation)", "?".yellow());
    }

    println!();
    output::item_warn("Config files already applied to ~ will remain as plain files.");
}

fn print_entry(path: &Path) {
    if path.exists() {
        println!("  {}  {}", "→".dimmed(), path.display().to_string().dimmed());
    } else {
        println!("  {}  {} (not found)", "·".dimmed(), path.display().to_string().dimmed());
    }
}

fn remove_config(path: &Path) -> Result<()> {
    if path.exists() {
        std::fs::remove_file(path)?;
        output::item_ok(&format!("removed {}", path.display()));
    }
    Ok(())
}

fn remove_chezmoidata(path: Option<&Path>) -> Result<()> {
    let Some(p) = path else { return Ok(()) };
    if p.exists() {
        std::fs::remove_file(p)?;
        output::item_ok(&format!("removed {}", p.display()));
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
    // Determinate Systems installer supports clean uninstall via receipt
    let determinate = Path::new("/nix/nix-installer");

    let status = if determinate.exists() {
        output::item("running Determinate Systems nix-installer uninstall...");
        Command::new(determinate).arg("uninstall").status()?
    } else {
        output::item("running official Nix uninstall script...");
        Command::new("sh")
            .args([
                "-c",
                "curl -sSfL https://install.determinate.systems/nix | sh -s -- uninstall",
            ])
            .status()?
    };

    if !status.success() {
        anyhow::bail!("Nix uninstall failed — remove manually: https://nixos.org/manual/nix/stable/#sect-macos-installation");
    }

    output::item_ok("Nix removed");
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    fn fixture_path(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name)
    }

    fn fixture_engine() -> kaizen_core::KaizenEngine {
        kaizen_core::KaizenEngine::new(fixture_path("features"))
    }

    #[test]
    fn dry_run_does_not_remove_files() {
        let dir = tempfile::tempdir().unwrap();
        let config = dir.path().join("config.toml");
        std::fs::write(&config, "schema_version = 1\n").unwrap();

        run(&fixture_engine(), &config, true).unwrap();

        assert!(config.exists(), "config must not be removed in dry-run");
    }
}
