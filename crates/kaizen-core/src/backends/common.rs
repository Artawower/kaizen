use crate::{
    chezmoi::{self, merge_chezmoidata_with},
    chezmoi_client::ChezmoiClient,
    container::ContainerCleaner,
    fs::FileSystem,
    process,
    progress::ProgressReporter,
    sync_backend::{ApplyReport, CleanReport},
    ConfigPlan, KaizenError, PackageManagerKind, TargetOs,
};

pub fn chezmoi_write_and_apply(
    plan: &ConfigPlan,
    dry_run: bool,
    reporter: &dyn ProgressReporter,
    client: &dyn ChezmoiClient,
    fs: &dyn FileSystem,
) -> Result<ApplyReport, KaizenError> {
    if dry_run {
        return Ok(ApplyReport { data_path: None });
    }

    let source_dir = match client.source_path()? {
        Some(p) => p,
        None => {
            let url = plan
                .dotfiles_source
                .as_deref()
                .ok_or(KaizenError::ChezmoidataTargetUnknown)?;
            client.init_source(url)?;
            client
                .source_path()?
                .ok_or(KaizenError::ChezmoidataTargetUnknown)?
        }
    };

    let data_path = source_dir.join(".chezmoidata.toml");

    if let Some(parent) = data_path.parent() {
        fs.create_dir_all(parent)?;
    }

    let content = merge_chezmoidata_with(&data_path, plan, fs)?;
    fs.write(&data_path, content.as_bytes())?;

    reporter.step("→ chezmoi apply");
    client.apply()?;

    Ok(ApplyReport {
        data_path: Some(data_path),
    })
}

pub fn os_cache_clean(os: &TargetOs, dry_run: bool) -> Result<(), KaizenError> {
    let (bin, args): (&str, &[&str]) = match os.package_manager_kind() {
        PackageManagerKind::Brew => ("brew", &["cleanup"]),
        PackageManagerKind::Dnf => ("dnf", &["clean", "all"]),
        PackageManagerKind::Apt => ("apt-get", &["clean"]),
        PackageManagerKind::Pacman => ("paccache", &["-r"]),
        PackageManagerKind::Unknown => return Ok(()),
    };
    run_optional(bin, args, dry_run)
}

pub fn clean_report_from_steps(steps: Vec<String>) -> CleanReport {
    CleanReport {
        freed_bytes: None,
        steps,
    }
}

pub fn clean_steps(
    os: &TargetOs,
    include_nix: bool,
    container: &dyn ContainerCleaner,
) -> Vec<String> {
    let mut steps = vec![];
    if include_nix {
        steps.push("nix-collect-garbage --delete-older-than 7d".into());
        steps.push("nix-store --optimise".into());
    }
    let pm_cmd = match os.package_manager_kind() {
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

fn run_optional(bin: &str, args: &[&str], dry_run: bool) -> Result<(), KaizenError> {
    if dry_run {
        return Ok(());
    }
    process::run_cmd_if_available(bin, args)
}

// Keep `chezmoi` in scope for tests that use it
#[allow(unused_imports)]
use chezmoi as _;
