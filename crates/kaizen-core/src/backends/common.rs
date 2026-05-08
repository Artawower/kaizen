use std::process::Command;

use crate::{
    chezmoi,
    sync_backend::{ApplyReport, CleanReport},
    ConfigPlan, KaizenError, PackageManagerKind, TargetOs,
};

pub fn chezmoi_write_and_apply(
    plan: &ConfigPlan,
    dry_run: bool,
) -> Result<ApplyReport, KaizenError> {
    let initial = chezmoi::source_path(plan)?;

    if dry_run {
        return Ok(ApplyReport { data_path: None });
    }

    let source_dir = initial.into_confirmed()?;
    let data_path = source_dir.join(".chezmoidata.toml");

    if let Some(parent) = data_path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let content = chezmoi::merge_chezmoidata(&data_path, plan)?;
    std::fs::write(&data_path, &content)?;

    let output = Command::new("chezmoi").arg("apply").output()?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        return Err(KaizenError::ChezmoidataApplyFailed {
            code: output.status.code(),
            reason: if stderr.is_empty() {
                None
            } else {
                Some(stderr)
            },
        });
    }

    Ok(ApplyReport {
        data_path: Some(data_path),
    })
}

pub fn mise_install(dry_run: bool) -> Result<(), KaizenError> {
    if dry_run {
        return Ok(());
    }

    let status = Command::new("mise").arg("install").status()?;
    if !status.success() {
        return Err(KaizenError::CommandFailed {
            cmd: "mise install".into(),
            code: status.code(),
        });
    }

    let mise_toml = dirs::home_dir()
        .ok_or(KaizenError::HomeDirUnavailable)?
        .join(".config/mise.toml");

    if mise_toml.exists() {
        let status = Command::new("mise").arg("trust").arg(&mise_toml).status()?;
        if !status.success() {
            return Err(KaizenError::CommandFailed {
                cmd: "mise trust".into(),
                code: status.code(),
            });
        }
    }

    Ok(())
}

pub fn mise_upgrade(tools: &[String], dry_run: bool) -> Result<(), KaizenError> {
    if dry_run {
        return Ok(());
    }
    let mut cmd = Command::new("mise");
    cmd.arg("upgrade");
    cmd.args(tools);
    let status = cmd.status()?;
    if !status.success() {
        return Err(KaizenError::CommandFailed {
            cmd: "mise upgrade".into(),
            code: status.code(),
        });
    }
    Ok(())
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

pub fn docker_clean(dry_run: bool) -> Result<(), KaizenError> {
    if which::which("docker").is_err() {
        return Ok(());
    }
    run_optional("docker", &["system", "prune", "-f"], dry_run)
}

pub fn clean_report_from_steps(steps: Vec<String>) -> CleanReport {
    CleanReport {
        freed_bytes: None,
        steps,
    }
}

pub fn clean_steps(os: &TargetOs, include_nix: bool) -> Vec<String> {
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
    if which::which("docker").is_ok() {
        steps.push("docker system prune -f".into());
    }
    steps
}

fn run_optional(bin: &str, args: &[&str], dry_run: bool) -> Result<(), KaizenError> {
    if dry_run {
        return Ok(());
    }
    if which::which(bin).is_err() {
        return Ok(());
    }
    let status = Command::new(bin).args(args).status()?;
    if !status.success() {
        return Err(KaizenError::CommandFailed {
            cmd: format!("{bin} {}", args.join(" ")),
            code: status.code(),
        });
    }
    Ok(())
}
