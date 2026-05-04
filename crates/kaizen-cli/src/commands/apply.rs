use std::path::{Path, PathBuf};

use anyhow::Result;
use dialoguer::Select;
use kaizen_core::chezmoi::SourcePathState;
use kaizen_core::{ConfigPlan, HookRunner, KaizenEngine, ShellHookRunner, TargetOs};
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
    let initial_state = kaizen_core::chezmoi::source_path(&plan.config_plan)?;
    let content = kaizen_core::chezmoi::generate_chezmoidata(&plan.config_plan)?;

    output::header("Chezmoi data");

    if dry_run {
        output::kv("source dir", &initial_state.path().display().to_string());
        println!();
        preview_state(&initial_state, &plan.config_plan.dotfiles_source)?;
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

    let Some(source_dir) = ensure_chezmoi_ready(
        &plan.config_plan,
        initial_state,
        plan.config_plan.dotfiles_source.as_deref(),
    )?
    else {
        println!("  Cancelled.");
        return Ok(());
    };
    let data_path = source_dir.join(".chezmoidata.toml");

    output::kv("source dir", &source_dir.display().to_string());
    output::kv("data file", &data_path.display().to_string());
    println!();

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

fn preview_state(state: &SourcePathState, configured: &Option<String>) -> Result<()> {
    match (state, configured.as_deref()) {
        (SourcePathState::Uninitialized(_), Some(src)) => {
            output::item_warn(&format!(
                "chezmoi not initialized — would run: chezmoi init {src}"
            ));
        }
        (SourcePathState::Uninitialized(_), None) => {
            output::item_err("preview only; real run would fail (no dotfiles.source set)");
        }
        (SourcePathState::Confirmed(path), Some(configured)) => {
            if let Some(current) = kaizen_core::chezmoi::current_remote(path)? {
                if !remotes_match(&current, configured) {
                    output::item_warn("remote conflict — would prompt for backup on real run:");
                    output::kv("  current   ", &current);
                    output::kv("  configured", configured);
                }
            }
        }
        (SourcePathState::Confirmed(_), None) => {}
    }
    Ok(())
}

fn ensure_chezmoi_ready(
    config_plan: &ConfigPlan,
    initial: SourcePathState,
    configured: Option<&str>,
) -> Result<Option<PathBuf>> {
    let source_dir = match initial {
        SourcePathState::Uninitialized(_) => {
            let Some(src) = configured else {
                anyhow::bail!(
                    "chezmoi not initialized and no dotfiles.source configured — run 'chezmoi init' first or set dotfiles.source"
                );
            };
            output::header("chezmoi init");
            chezmoi_init(src)?;
            output::item_ok("chezmoi init done");
            println!();
            kaizen_core::chezmoi::source_path(config_plan)?.into_confirmed()?
        }
        SourcePathState::Confirmed(path) => {
            match (configured, kaizen_core::chezmoi::current_remote(&path)?) {
                (Some(cfg), Some(current)) if !remotes_match(&current, cfg) => {
                    if !resolve_conflict(&path, &current, cfg)? {
                        return Ok(None);
                    }
                    kaizen_core::chezmoi::source_path(config_plan)?.into_confirmed()?
                }
                _ => path,
            }
        }
    };
    Ok(Some(source_dir))
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

    chezmoi_init(configured)
        .map_err(|e| anyhow::anyhow!("{e} — backup preserved at {}", backup.display()))?;
    output::item_ok("chezmoi reinit done");
    println!();
    Ok(true)
}

fn chezmoi_init(source: &str) -> Result<()> {
    let status = std::process::Command::new("chezmoi")
        .args(["init", source])
        .status()?;
    if !status.success() {
        anyhow::bail!(
            "chezmoi init failed with exit code {}",
            status.code().unwrap_or(-1)
        );
    }
    Ok(())
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
