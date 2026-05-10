use std::env;
use std::process::Command;

use anyhow::{bail, Context, Result};
use owo_colors::OwoColorize;

use crate::output;

const REPO: &str = "artawower/kaizen";
const INSTALL_SCRIPT: &str = "https://raw.githubusercontent.com/artawower/kaizen/master/install.sh";

pub fn run(dry_run: bool) -> Result<()> {
    output::page_header("self-update");

    let current = current_version();
    output::kv("current version", &current);

    let latest = fetch_latest().context("failed to fetch latest release from GitHub")?;
    output::kv("latest version", &latest);

    if current != "unknown" && versions_equal(&current, &latest) {
        println!();
        output::item_ok("already up to date");
        return Ok(());
    }

    println!();
    if dry_run {
        println!(
            "  {} would upgrade {} → {}",
            "→".dimmed(),
            current.yellow(),
            latest.green()
        );
        println!();
        println!("  Run without --dry-run to apply.");
        return Ok(());
    }

    output::item(&format!(
        "upgrading {} → {}",
        current.yellow(),
        latest.green()
    ));

    let binary_path =
        env::current_exe().context("cannot determine path of running kaizen binary")?;

    download_and_replace(&binary_path.to_string_lossy())?;

    println!();
    output::item_ok(&format!("upgraded to {latest}"));
    Ok(())
}

fn current_version() -> String {
    let out = Command::new("kaizen").arg("--version").output();
    match out {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout)
            .trim()
            .split_once(' ')
            .map(|x| x.1)
            .unwrap_or("unknown")
            .trim()
            .to_owned(),
        _ => "unknown".to_owned(),
    }
}

pub fn fetch_latest() -> Result<String> {
    let url = format!("https://api.github.com/repos/{REPO}/releases/latest");
    let out = Command::new("curl")
        .args([
            "-fsSL",
            "--header",
            "Accept: application/vnd.github+json",
            "--header",
            "X-GitHub-Api-Version: 2022-11-28",
            &url,
        ])
        .output()
        .context("curl not found")?;

    if !out.status.success() {
        bail!(
            "GitHub API returned non-zero exit: {}",
            String::from_utf8_lossy(&out.stderr)
        );
    }

    let body = String::from_utf8_lossy(&out.stdout);
    parse_tag_name(&body)
        .ok_or_else(|| anyhow::anyhow!("could not parse tag_name from GitHub response"))
}

fn parse_tag_name(json: &str) -> Option<String> {
    // Minimal JSON extraction — no extra dependencies.
    let key = "\"tag_name\"";
    let start = json.find(key)? + key.len();
    let after_colon = json[start..].find('"')? + start + 1;
    let end = json[after_colon..].find('"')? + after_colon;
    Some(json[after_colon..end].to_owned())
}

pub fn versions_equal(a: &str, b: &str) -> bool {
    a.trim_start_matches('v') == b.trim_start_matches('v')
}

fn download_and_replace(binary_path: &str) -> Result<()> {
    let status = Command::new("sh")
        .args([
            "-c",
            &format!(
                "curl -fsSL {INSTALL_SCRIPT} | sh -s -- --to {dir}",
                dir = std::path::Path::new(binary_path)
                    .parent()
                    .map(|p| p.to_string_lossy().into_owned())
                    .unwrap_or_else(|| "/usr/local/bin".to_owned())
            ),
        ])
        .status()
        .context("failed to run install script")?;

    if !status.success() {
        bail!("install script failed — run manually: curl -fsSL {INSTALL_SCRIPT} | sh");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_tag_name_from_github_response() {
        let json = r#"{"tag_name":"v0.4.0","name":"Kaizen v0.4.0"}"#;
        assert_eq!(parse_tag_name(json).as_deref(), Some("v0.4.0"));
    }

    #[test]
    fn versions_equal_ignores_v_prefix() {
        assert!(versions_equal("0.4.0", "v0.4.0"));
        assert!(versions_equal("v0.4.0", "v0.4.0"));
        assert!(!versions_equal("0.3.0", "v0.4.0"));
    }
}
