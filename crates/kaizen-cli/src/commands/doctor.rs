use std::path::Path;

use anyhow::Result;
use kaizen_core::KaizenEngine;
use owo_colors::OwoColorize;

use crate::ensure::Tool;
use crate::{ensure, output};

pub fn run(engine: &KaizenEngine, config_path: &Path) -> Result<()> {
    output::page_header("doctor");

    output::header("System");
    output::kv("OS", &kaizen_core::TargetOs::detect().to_string());
    output::kv("arch", std::env::consts::ARCH);

    output::header("Tools");
    for tool in ensure::ALL {
        report_tool(tool);
    }

    report_nix_tools();
    report_nix_uninstall_state();
    report_config(engine, config_path);
    report_dotfiles_source();
    report_version();

    output::header("Features");
    match engine.list_features() {
        Ok(names) if !names.is_empty() => {
            output::item_ok(&format!("{} feature(s) available", names.len()))
        }
        Ok(_) => output::item_warn("features dir is empty"),
        Err(e) => output::item_err(&e.to_string()),
    }

    println!();
    Ok(())
}

fn report_nix_uninstall_state() {
    use std::path::Path;

    let nix_store = Path::new("/nix/store");
    if !nix_store.exists() {
        return; // Nix not installed, nothing to report
    }

    output::header("Nix uninstall info");

    // Determinate Systems: receipt is the key to automated uninstall
    let receipt = Path::new("/nix/receipt.json");
    let installer_bin = Path::new("/nix/nix-installer");

    if installer_bin.exists() {
        output::item_ok("nix-installer binary found — automated uninstall available");
        output::item(&format!("  run: {} uninstall", installer_bin.display()));
    } else if receipt.exists() {
        output::item_warn("nix-installer binary missing but receipt found");
        output::item("  download matching installer version and run with 'uninstall'");
        output::item("  see: https://docs.determinate.systems/determinate-nix/#uninstalling");
    } else {
        output::item_warn(
            "nix-installer binary and receipt both missing — manual uninstall required",
        );
        output::item(
            "  Determinate: https://docs.determinate.systems/determinate-nix/#uninstalling",
        );
        output::item("  Official:    https://nixos.org/manual/nix/stable/#sect-macos-installation");
    }

    // APFS volume
    let apfs_vol = std::process::Command::new("diskutil")
        .args(["info", "/nix"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .is_some();
    if apfs_vol {
        output::item_ok("/nix APFS volume detected");
    }
}

fn report_nix_tools() {
    let any_nix = ensure::NIX_TOOLS
        .iter()
        .any(|t| which::which(t.name).is_ok());

    if !any_nix {
        return;
    }

    output::header("Nix");
    for tool in ensure::NIX_TOOLS {
        report_tool(tool);
    }
}

fn report_tool(tool: &Tool) {
    match which::which(tool.name) {
        Ok(path) => output::item_ok(&format!(
            "{:<12} {}",
            tool.name,
            path.display().to_string().dimmed()
        )),
        Err(_) => output::item_err(&format!(
            "{:<12} not found  ({})",
            tool.name,
            tool.install_hint.dimmed()
        )),
    }
}

fn report_dotfiles_source() {
    use kaizen_core::ChezmoiClient as _;

    output::header("Dotfiles source");

    let client = crate::chezmoi::StdChezmoiClient;

    // Resolve the chezmoi source dir (may be a symlink).
    let chezmoi_dir = dirs::home_dir().map(|h| h.join(".local/share/chezmoi"));
    let is_symlink = chezmoi_dir
        .as_deref()
        .and_then(|p| p.symlink_metadata().ok())
        .map(|m| m.file_type().is_symlink())
        .unwrap_or(false);

    let source = match client.source_root().unwrap_or(None) {
        Some(p) => p,
        None => {
            output::item_warn("chezmoi source not initialized — run: kaizen install");
            return;
        }
    };

    output::kv(
        "path",
        &format!(
            "{}  {}",
            source.display(),
            if is_symlink {
                "(dev symlink)"
            } else {
                "(clone)"
            }
        ),
    );

    // Current commit.
    let commit = std::process::Command::new("git")
        .args([
            "-C",
            &source.to_string_lossy(),
            "rev-parse",
            "--short",
            "HEAD",
        ])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_owned());

    match &commit {
        Some(c) => output::kv("commit", c),
        None => output::item_warn("not a git repository"),
    }

    // Dirty working tree (uncommitted changes visible to chezmoi).
    let dirty = std::process::Command::new("git")
        .args(["-C", &source.to_string_lossy(), "status", "--porcelain"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| !o.stdout.is_empty())
        .unwrap_or(false);

    if dirty {
        output::item_warn("working tree has uncommitted changes — chezmoi sees local state");
    } else {
        output::item_ok("working tree clean");
    }

    // Remote staleness check (only for real clones — symlinks are managed by the dev).
    // Uses cached remote refs — no network call so doctor stays fast offline.
    if !is_symlink {
        let dir = source.to_string_lossy().into_owned();

        // Resolve upstream tracking ref (@{u}), fall back to origin/master.
        let upstream = std::process::Command::new("git")
            .args([
                "-C",
                &dir,
                "rev-parse",
                "--abbrev-ref",
                "--symbolic-full-name",
                "@{u}",
            ])
            .output()
            .ok()
            .filter(|o| o.status.success())
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .map(|s| s.trim().to_owned())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "origin/master".to_owned());

        let count = |range: String| {
            std::process::Command::new("git")
                .args(["-C", &dir, "rev-list", "--count", &range])
                .output()
                .ok()
                .filter(|o| o.status.success())
                .and_then(|o| String::from_utf8(o.stdout).ok())
                .and_then(|s| s.trim().parse::<u32>().ok())
                .unwrap_or(0)
        };

        let behind = count(format!("HEAD..{upstream}"));
        let ahead = count(format!("{upstream}..HEAD"));

        match (behind > 0, ahead > 0) {
            (true, true) => output::item_warn(&format!(
                "{behind} commit(s) behind, {ahead} ahead — diverged. run: kaizen sync"
            )),
            (true, false) => output::item_warn(&format!(
                "{behind} commit(s) behind remote — run: kaizen sync"
            )),
            (false, true) => output::item_warn(&format!("{ahead} local commit(s) not pushed")),
            (false, false) => output::item_ok("up to date with remote (cached refs)"),
        }
    }
}

fn report_version() {
    use super::self_update::{fetch_latest, versions_equal};

    output::header("Version");
    let current = env!("CARGO_PKG_VERSION");
    output::kv("installed", current);

    match fetch_latest() {
        Ok(latest) if versions_equal(current, &latest) => {
            output::item_ok("up to date");
        }
        Ok(latest) => {
            output::item_warn(&format!(
                "update available: {current} → {}  (run: kaizen self-update)",
                latest.green()
            ));
        }
        Err(_) => {
            output::item_warn("could not check for updates (offline?)");
        }
    }
}

fn report_config(engine: &KaizenEngine, config_path: &Path) {
    output::header("Config");

    if !config_path.exists() {
        output::item_err(&format!(
            "{} not found  (run: kaizen install)",
            config_path.display()
        ));
        return;
    }

    output::item_ok(&format!("{}", config_path.display()));

    match engine.load_config(config_path) {
        Ok(cfg) => {
            output::warn_if_schema_outdated(&cfg);
            let n = cfg.features.values().filter(|f| f.enabled).count();
            output::kv("  enabled features", &n.to_string());
        }
        Err(e) => output::item_err(&format!("parse error: {e}")),
    }
}
