use std::path::Path;

use anyhow::Result;
use dialoguer::Select;
use kaizen_core::{HookRunner, KaizenEngine, ShellHookRunner, TargetOs};
use owo_colors::OwoColorize;

use crate::{ensure, hooks, output};

pub fn run(engine: &KaizenEngine, config_path: &Path, dry_run: bool) -> Result<()> {
    run_with(engine, config_path, dry_run, &ShellHookRunner)
}

fn run_with(
    engine: &KaizenEngine,
    config_path: &Path,
    dry_run: bool,
    hook_runner: &dyn HookRunner,
) -> Result<()> {
    output::page_header(if dry_run { "apply  (dry-run)" } else { "apply" });

    let config = engine.load_config(config_path)?;
    output::warn_if_schema_outdated(&config);

    let plan = engine.build_workflow_plan(&config, TargetOs::detect())?;
    let (source_dir, is_fallback) = kaizen_core::chezmoi::source_path(&plan.config_plan)?;
    let data_path = source_dir.join(".chezmoidata.toml");
    let content = kaizen_core::chezmoi::generate_chezmoidata(&plan.config_plan)?;

    output::header("Chezmoi data");
    output::kv("source dir", &source_dir.display().to_string());
    output::kv("data file", &data_path.display().to_string());
    println!();

    if dry_run {
        if is_fallback {
            output::item_warn("chezmoi source dir not confirmed — run 'chezmoi init' first");
        } else if let Some(configured) = &plan.config_plan.dotfiles_source {
            if let Some(current) = kaizen_core::chezmoi::current_remote(&source_dir)? {
                if !remotes_match(&current, configured) {
                    output::item_warn("remote conflict — would prompt for backup on real run:");
                    output::kv("  current   ", &current);
                    output::kv("  configured", configured);
                }
            }
        }
        println!("{}", "  --- .chezmoidata.toml ---".dimmed());
        for line in content.lines() {
            println!("  {}", line.dimmed());
        }
        println!();
        println!("  Run without --dry-run to write + apply.");
        hooks::run(&plan.hook_plan.post_apply, true, hook_runner)?;
        return Ok(());
    }

    ensure::require(&[&ensure::CHEZMOI])?;

    if is_fallback {
        anyhow::bail!("chezmoi source directory not confirmed — run 'chezmoi init' first");
    }

    if let Some(configured) = &plan.config_plan.dotfiles_source {
        match kaizen_core::chezmoi::current_remote(&source_dir)? {
            Some(current) if !remotes_match(&current, configured) => {
                if !resolve_conflict(&source_dir, &current, configured)? {
                    println!("  Cancelled.");
                    return Ok(());
                }
            }
            _ => {}
        }
    }

    if let Some(parent) = data_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&data_path, &content)?;
    output::item_ok(&format!("wrote {}", data_path.display()));
    println!();

    output::header("chezmoi apply");
    let status = std::process::Command::new("chezmoi")
        .arg("apply")
        .status()?;
    if !status.success() {
        anyhow::bail!(
            "chezmoi apply failed with exit code {}",
            status.code().unwrap_or(-1)
        );
    }
    output::item_ok("chezmoi apply done");
    println!();

    hooks::run(&plan.hook_plan.post_apply, false, hook_runner)
}

fn remotes_match(a: &str, b: &str) -> bool {
    canonical_remote(a) == canonical_remote(b)
}

fn canonical_remote(r: &str) -> String {
    let r = r.trim().trim_end_matches('/').trim_end_matches(".git");
    // SCP-style: git@github.com:user/repo
    if let Some(rest) = r.strip_prefix("git@") {
        if let Some(pos) = rest.find(':') {
            return format!("{}/{}", &rest[..pos], &rest[pos + 1..]).to_lowercase();
        }
    }
    // URL-style: https://host/path or ssh://user@host/path
    if let Some(idx) = r.find("://") {
        let after_scheme = &r[idx + 3..];
        let after_user = after_scheme
            .find('@')
            .map(|i| &after_scheme[i + 1..])
            .unwrap_or(after_scheme);
        return after_user.to_lowercase();
    }
    r.to_lowercase()
}

fn resolve_conflict(source_dir: &Path, current: &str, configured: &str) -> Result<bool> {
    println!();
    output::item_warn("chezmoi is already initialized with a different remote:");
    output::kv("  current   ", current);
    output::kv("  configured", configured);
    println!();

    let options = [
        "Cancel",
        "Backup existing source dir and reinit from configured remote",
    ];
    let choice = Select::new()
        .with_prompt("What would you like to do?")
        .items(options)
        .default(0)
        .interact()?;

    if choice == 0 {
        return Ok(false);
    }

    let backup = kaizen_core::chezmoi::backup_source_dir(source_dir)?;
    output::item_ok(&format!("backed up to {}", backup.display()));

    let status = std::process::Command::new("chezmoi")
        .args(["init", configured])
        .status()?;
    if !status.success() {
        anyhow::bail!(
            "chezmoi init failed — backup preserved at {}",
            backup.display()
        );
    }
    output::item_ok("chezmoi reinit done");
    println!();
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remotes_match_ssh_and_https_same_repo() {
        assert!(remotes_match(
            "git@github.com:user/repo.git",
            "https://github.com/user/repo"
        ));
    }

    #[test]
    fn remotes_match_ssh_url_style() {
        assert!(remotes_match(
            "ssh://git@github.com/user/repo.git",
            "https://github.com/user/repo"
        ));
    }

    #[test]
    fn remotes_match_identical() {
        assert!(remotes_match(
            "https://github.com/user/repo",
            "https://github.com/user/repo"
        ));
    }

    #[test]
    fn remotes_differ_on_different_paths() {
        assert!(!remotes_match(
            "git@github.com:user/repo-a.git",
            "git@github.com:user/repo-b.git"
        ));
    }

    #[test]
    fn remotes_differ_on_different_users() {
        assert!(!remotes_match(
            "https://github.com/alice/repo",
            "https://github.com/bob/repo"
        ));
    }
}
