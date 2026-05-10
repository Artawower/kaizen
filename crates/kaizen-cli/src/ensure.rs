use std::process::Command;

use anyhow::{bail, Result};
use owo_colors::OwoColorize;

use crate::output;

pub struct Tool {
    pub name: &'static str,
    pub install_hint: &'static str,
}

pub const CHEZMOI: Tool = Tool {
    name: "chezmoi",
    install_hint: "https://www.chezmoi.io/install/",
};

pub const MISE: Tool = Tool {
    name: "mise",
    install_hint: "https://mise.jdx.dev",
};

pub const HOME_MANAGER: Tool = Tool {
    name: "home-manager",
    install_hint: "https://nix-community.github.io/home-manager/",
};

pub const DARWIN_REBUILD: Tool = Tool {
    name: "darwin-rebuild",
    install_hint: "https://github.com/LnL7/nix-darwin",
};

pub const NIX: Tool = Tool {
    name: "nix",
    install_hint: "https://install.determinate.systems/nix",
};

/// Core tools required for kaizen to function.
pub const ALL: &[&Tool] = &[&CHEZMOI, &MISE];

/// Nix-related tools checked by `kaizen doctor` when Nix backend is in use.
pub const NIX_TOOLS: &[&Tool] = &[&NIX, &HOME_MANAGER, &DARWIN_REBUILD];

/// Ensure chezmoi is available, installing it automatically if missing.
///
/// Uses the official chezmoi installer: https://www.chezmoi.io/install/
/// Installs to `~/.local/bin` so no sudo is required.
pub fn ensure_chezmoi() -> Result<()> {
    if which::which("chezmoi").is_ok() {
        return Ok(());
    }

    output::item_warn("chezmoi not found — installing via official installer…");

    let bin_dir = dirs::home_dir()
        .map(|h| h.join(".local/bin"))
        .ok_or_else(|| anyhow::anyhow!("cannot determine home directory"))?;

    std::fs::create_dir_all(&bin_dir)?;

    let status = Command::new("sh")
        .args([
            "-c",
            &format!(
                "$(curl -fsLS get.chezmoi.io) -- -b {}",
                bin_dir.to_string_lossy()
            ),
        ])
        .status()?;

    if !status.success() {
        bail!(
            "chezmoi installation failed.\nInstall manually: {}",
            CHEZMOI.install_hint.dimmed()
        );
    }

    output::item_ok(&format!("chezmoi installed to {}", bin_dir.display()));

    // Extend PATH for the current process so subsequent chezmoi calls find it.
    let current_path = std::env::var("PATH").unwrap_or_default();
    let bin_str = bin_dir.to_string_lossy();
    if !current_path.contains(bin_str.as_ref()) {
        std::env::set_var("PATH", format!("{}:{current_path}", bin_dir.display()));
    }

    Ok(())
}

/// Ensure Nix is available on macOS, installing via Determinate Systems if missing.
///
/// Adds the Nix profile bin dir to PATH so `detect_backend` picks up the Nix
/// backend in the same run without requiring a new shell.
pub fn ensure_nix_macos() -> Result<()> {
    if which::which("nix").is_ok()
        || which::which("home-manager").is_ok()
        || which::which("darwin-rebuild").is_ok()
    {
        return Ok(());
    }

    output::item_warn("Nix not found — installing via Determinate Systems…");
    output::item("This requires sudo and takes about a minute.");

    let nix_installer_url = "https://install.determinate.systems/nix";
    let fetch_cmd = format!(
        "curl --proto '=https' --tlsv1.2 -sSfL {nix_installer_url} \
         | sh -s -- install --no-confirm"
    );
    let status = Command::new("sh").args(["-c", &fetch_cmd]).status()?;

    if !status.success() {
        bail!(
            "Nix installation failed.\nInstall manually: {}",
            NIX.install_hint.dimmed()
        );
    }

    output::item_ok("Nix installed");

    // Extend PATH so detect_backend finds nix/home-manager/darwin-rebuild.
    let nix_bin = "/nix/var/nix/profiles/default/bin";
    let path = std::env::var("PATH").unwrap_or_default();
    if !path.contains(nix_bin) {
        std::env::set_var("PATH", format!("{nix_bin}:{path}"));
    }

    output::item_warn(
        "Open a new terminal after install, or run:\n  \
         source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh",
    );

    Ok(())
}
