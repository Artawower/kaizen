use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use kaizen_core::KaizenEngine;

use kaizen_core::ChezmoiClient;

use crate::{chezmoi::StdChezmoiClient, commands, ensure, output};

/// Returns `true` when running from a `cargo`-built binary inside `target/debug` or `target/release`.
fn is_dev_build() -> bool {
    std::env::current_exe()
        .map(|p| {
            let comps: Vec<_> = p.components().map(|c| c.as_os_str().to_owned()).collect();
            comps
                .windows(2)
                .any(|w| w[0] == "target" && (w[1] == "debug" || w[1] == "release"))
        })
        .unwrap_or(false)
}

/// Walk up from the binary to find the project root (directory containing `Cargo.toml`).
fn dev_project_root() -> Option<PathBuf> {
    let exe = std::env::current_exe().ok()?;
    let mut dir = exe.parent()?; // .../target/debug
    loop {
        if dir.join("Cargo.toml").exists() {
            return Some(dir.to_owned());
        }
        dir = dir.parent()?;
    }
}

/// When running a dev build and chezmoi source does not yet exist,
/// create `~/.local/share/chezmoi → <project root>` instead of cloning.
/// This makes `just run install` work out of the box without `just dev-link`.
fn ensure_dev_symlink() -> Result<()> {
    let chezmoi_dir = dirs::home_dir()
        .map(|h| h.join(".local/share/chezmoi"))
        .ok_or_else(|| anyhow::anyhow!("cannot determine home directory"))?;

    // Already a symlink — dev workflow is correct, nothing to do.
    if chezmoi_dir
        .symlink_metadata()
        .map(|m| m.file_type().is_symlink())
        .unwrap_or(false)
    {
        return Ok(());
    }

    // Real directory exists (e.g. a previous `kaizen install` cloned it).
    // Back it up and replace with the dev symlink.
    if chezmoi_dir.exists() {
        // jj always has an active working-copy commit so `git status` is
        // meaningless there — skip the dirty check for jj repos.
        let is_jj = chezmoi_dir.join(".jj").exists()
            || chezmoi_dir
                .parent()
                .map(|p| p.join(".jj").exists())
                .unwrap_or(false);

        if is_jj {
            output::item_warn("jj repo detected — skipping dirty check, trusting you");
        } else {
            let dirty = std::process::Command::new("git")
                .args([
                    "-C",
                    &chezmoi_dir.to_string_lossy(),
                    "status",
                    "--porcelain",
                ])
                .output()
                .map(|o| !o.stdout.is_empty())
                .unwrap_or(false);

            if dirty {
                output::item_warn(
                    "~/.local/share/chezmoi has uncommitted changes — not replacing with symlink.",
                );
                output::item("  Commit or stash, then re-run.");
                return Ok(());
            }
        }

        // Use backup_source_dir so the old clone is preserved, not destroyed.
        use kaizen_core::ChezmoiClient as _;
        let backup = StdChezmoiClient.backup_source_dir(&chezmoi_dir)?;
        output::item_ok(&format!(
            "backed up existing clone to {}",
            backup.backup_path.display()
        ));
    }

    let root = dev_project_root()
        .ok_or_else(|| anyhow::anyhow!("cannot locate project root from dev binary"))?;

    if let Some(parent) = chezmoi_dir.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::os::unix::fs::symlink(&root, &chezmoi_dir)?;
    output::item_ok(&format!(
        "dev symlink created: {} → {}",
        chezmoi_dir.display(),
        root.display()
    ));
    Ok(())
}

/// First-time machine install: configure if needed, then sync.
///
/// Runs the configure wizard when EITHER:
/// - config does not exist yet, OR
/// - chezmoi source is not initialized (dotfiles not cloned)
///
/// This ensures that on a fresh machine the user is always asked for
/// the dotfiles URL even if a stale config already exists.
pub fn run(
    engine: &KaizenEngine,
    features_dir: Option<&Path>,
    config_path: &Path,
    dry_run: bool,
) -> Result<()> {
    // In a dev build, wire up the symlink before anything else so chezmoi
    // picks up the working repo directly. In a release build, update the
    // binary from GitHub releases instead.
    let dev_build = is_dev_build();
    if dev_build {
        ensure_dev_symlink()?;
    } else if !dry_run {
        let _ = commands::self_update::run(false);
    }

    let config_exists = config_path.exists();
    let source_path = StdChezmoiClient.source_path().unwrap_or(None);
    let chezmoi_ready = source_path.is_some();

    if !dev_build && !dry_run {
        if let Some(source) = source_path.as_ref() {
            output::item(&format!("updating dotfiles source {} …", source.display()));
            StdChezmoiClient
                .pull_source(source)
                .context("failed to update dotfiles source")?;
            output::item_ok("dotfiles source updated");
        }
    }

    let need_configure = !config_exists || !chezmoi_ready;

    if need_configure {
        if config_exists && !chezmoi_ready {
            output::item_warn("dotfiles not cloned yet — running configure to initialize chezmoi");
        }
        println!();
        output::page_header("install — configure");
        commands::configure::run(features_dir, config_path, false, false)?;
        println!();
    } else {
        output::item_ok("config and dotfiles found — skipping configure");
    }

    // On macOS, ensure Nix is installed before syncing so detect_backend
    // selects the Nix backend rather than falling back to upt/brew.
    if kaizen_core::TargetOs::detect() == kaizen_core::TargetOs::Darwin {
        ensure::ensure_nix_macos()?;
    }

    // install is a first-time setup command — always force-apply dotfiles
    // so chezmoi never prompts about locally modified managed files.
    commands::sync::run(engine, config_path, dry_run, true)
}
