use std::path::PathBuf;

use crate::{
    chezmoi::merge_kaizen_data_with,
    chezmoi_client::ChezmoiClient,
    container::ContainerCleaner,
    executor::{ProcessCommand, ProcessExecutor},
    fs::FileSystem,
    paths::PathProvider,
    progress::ProgressReporter,
    sync_backend::{ApplyReport, CleanReport},
    ConfigPlan, KaizenError, PackageManagerKind,
};

pub fn chezmoi_write_and_apply(
    plan: &ConfigPlan,
    dry_run: bool,
    force: bool,
    reporter: &dyn ProgressReporter,
    client: &dyn ChezmoiClient,
    fs: &dyn FileSystem,
    paths: &dyn PathProvider,
) -> Result<ApplyReport, KaizenError> {
    if dry_run {
        return Ok(ApplyReport { data_path: None });
    }

    // Ensure chezmoi source is initialized (clone dotfiles repo if needed).
    if client.source_path()?.is_none() {
        let url = plan
            .dotfiles_source
            .as_deref()
            .ok_or(KaizenError::ChezmoidataTargetUnknown)?;
        client.init_source(url)?;
    }

    // Pull latest dotfiles from remote before applying — but only when the
    // chezmoi source is a real clone, not a developer symlink.  When it is a
    // symlink the developer manages their own VCS and a silent pull would
    // overwrite uncommitted work.
    if !client.source_is_dev_symlink() {
        if let Some(source) = client.source_path()? {
            if let Some(git_root) = source.parent() {
                let _ = client.pull_source(git_root); // non-fatal: offline / no remote is fine
            }
        }
    }

    // Write features data and manifest to ~/.config/kaizen/.
    // chezmoi templates read data.toml via `include | fromToml`;
    // Nix options.nix reads manifest.toml via builtins.fromTOML.
    let data_path = write_kaizen_data(plan, paths, fs)?;
    copy_manifest_to_config(client, paths, fs)?;

    reporter.step("→ chezmoi apply");
    client.apply(force)?;

    Ok(ApplyReport {
        data_path: Some(data_path),
    })
}

/// Write features data to `~/.config/kaizen/data.toml` — the single source of truth.
///
/// Merges with any existing content so unknown keys (e.g. user-added data) are preserved.
fn write_kaizen_data(
    plan: &ConfigPlan,
    paths: &dyn PathProvider,
    fs: &dyn FileSystem,
) -> Result<PathBuf, KaizenError> {
    let config_dir = paths.config_dir().ok_or(KaizenError::HomeDirUnavailable)?;
    let kaizen_dir = config_dir.join("kaizen");
    let data_path = kaizen_dir.join("data.toml");
    fs.create_dir_all(&kaizen_dir)?;
    let content = merge_kaizen_data_with(&data_path, plan, fs)?;
    fs.write(&data_path, content.as_bytes())?;
    Ok(data_path)
}

/// Copy `manifest.toml` from the chezmoi source to `~/.config/kaizen/manifest.toml`
/// so that Nix `options.nix` can read it via `builtins.fromTOML` at eval time.
/// No-op when the chezmoi source is unavailable (e.g. first bootstrap).
fn copy_manifest_to_config(
    client: &dyn crate::chezmoi_client::ChezmoiClient,
    paths: &dyn crate::paths::PathProvider,
    fs: &dyn FileSystem,
) -> Result<(), KaizenError> {
    let Some(source) = client.source_path()? else {
        return Ok(());
    };
    let src = source
        .join(crate::manifest::KAIZEN_DIR)
        .join("manifest.toml");
    if !fs.exists(&src) {
        return Ok(());
    }
    let content = fs.read_to_string(&src)?;
    let kaizen_dir = paths
        .config_dir()
        .ok_or(KaizenError::HomeDirUnavailable)?
        .join("kaizen");
    fs.create_dir_all(&kaizen_dir)?;
    fs.write(&kaizen_dir.join("manifest.toml"), content.as_bytes())?;
    Ok(())
}

pub fn os_cache_clean(
    pm: &PackageManagerKind,
    dry_run: bool,
    executor: &dyn ProcessExecutor,
    paths: &dyn PathProvider,
) -> Result<(), KaizenError> {
    let (bin, args): (&str, &[&str]) = match pm {
        PackageManagerKind::Brew => ("brew", &["cleanup"]),
        PackageManagerKind::Dnf => ("dnf", &["clean", "all"]),
        PackageManagerKind::Apt => ("apt-get", &["clean"]),
        PackageManagerKind::Pacman => ("paccache", &["-r"]),
        PackageManagerKind::Unknown => return Ok(()),
    };
    run_if_available(bin, args, dry_run, executor, paths)
}

pub fn clean_report_from_steps(steps: Vec<String>) -> CleanReport {
    CleanReport {
        freed_bytes: None,
        steps,
    }
}

pub fn clean_steps(
    pm: &PackageManagerKind,
    include_nix: bool,
    container: &dyn ContainerCleaner,
) -> Vec<String> {
    let mut steps = vec![];
    if include_nix {
        steps.push("nix-collect-garbage --delete-older-than 7d".into());
        steps.push("nix-store --optimise".into());
    }
    let pm_cmd = match pm {
        PackageManagerKind::Brew => Some("brew cleanup"),
        PackageManagerKind::Dnf => Some("dnf clean all"),
        PackageManagerKind::Apt => Some("apt-get clean"),
        PackageManagerKind::Pacman => Some("paccache -r"),
        PackageManagerKind::Unknown => None,
    };
    if let Some(cmd) = pm_cmd {
        steps.push(cmd.into());
    }
    if let Some(step) = container.clean_step() {
        steps.push(step);
    }
    steps
}

/// Run `bin args` if the binary is on PATH, skipping when `dry_run`.
fn run_if_available(
    bin: &str,
    args: &[&str],
    dry_run: bool,
    executor: &dyn ProcessExecutor,
    paths: &dyn PathProvider,
) -> Result<(), KaizenError> {
    if dry_run || !paths.is_tool_available(bin) {
        return Ok(());
    }
    executor.execute(ProcessCommand::run(bin, args.iter().copied()))?;
    Ok(())
}
