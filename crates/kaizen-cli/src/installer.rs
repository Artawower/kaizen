use std::{env, process::Command};

use kaizen_core::{Installer, KaizenError, Remover, TargetOs, Updater};

/// Concrete upt-based package manager adapter.
///
/// Implements `Installer + Updater + Remover` for use with `UptSyncBackend`.
/// Lives in CLI, not in core, because it spawns concrete OS processes.
pub struct UptInstaller;

impl Installer for UptInstaller {
    fn install(&self, programs: &[String]) -> Result<(), KaizenError> {
        run_upt(&["install"], programs)
    }

    fn preview_install(&self, programs: &[String]) -> String {
        preview_upt(&["install"], programs)
    }
}

impl Updater for UptInstaller {
    fn upgrade(&self, programs: &[String]) -> Result<(), KaizenError> {
        run_upt(&["upgrade"], programs)
    }

    fn preview_upgrade(&self, programs: &[String]) -> String {
        preview_upt(&["upgrade"], programs)
    }
}

impl Remover for UptInstaller {
    fn remove(&self, programs: &[String]) -> Result<(), KaizenError> {
        run_upt(&["remove"], programs)
    }

    fn preview_remove(&self, programs: &[String]) -> String {
        preview_upt(&["remove"], programs)
    }
}

fn run_upt(args: &[&str], programs: &[String]) -> Result<(), KaizenError> {
    let mut failed = Vec::new();
    let mut last_code = None;
    let mut success_count = 0usize;

    for program in programs {
        let status = build_upt_command(args, program)?.status()?;
        if status.success() {
            success_count += 1;
            continue;
        }
        last_code = status.code();
        failed.push(program.clone());
    }

    if failed.is_empty() {
        return Ok(());
    }

    if success_count == 0 {
        return Err(KaizenError::InstallerFailed {
            installer: "upt",
            code: last_code,
        });
    }

    Err(KaizenError::InstallerPartialFailure {
        count: failed.len(),
        failed,
    })
}

fn build_upt_command(args: &[&str], program: &str) -> Result<Command, KaizenError> {
    let mut command = base_upt_command()?;
    command.args(args).arg("-y").arg(program);
    Ok(command)
}

fn base_upt_command() -> Result<Command, KaizenError> {
    if !should_use_sudo() {
        return Ok(Command::new("upt"));
    }

    let upt = which::which("upt").map_err(which_error_to_io)?;
    let mut command = Command::new("sudo");
    command.arg("-p").arg("[kaizen] sudo password: ");
    command.arg(upt);
    Ok(command)
}

fn preview_upt(args: &[&str], programs: &[String]) -> String {
    let prefix = if should_use_sudo() { "sudo " } else { "" };
    format!("{prefix}upt {} -y {}", args.join(" "), programs.join(" "))
}

fn should_use_sudo() -> bool {
    let policy = env::var("KAIZEN_SUDO").ok();
    if matches!(policy.as_deref(), Some("always")) {
        return true;
    }
    if matches!(policy.as_deref(), Some("never")) {
        return false;
    }
    should_use_sudo_for(
        TargetOs::detect(),
        is_effective_root(),
        env::var("UPT_TOOL").ok(),
    )
}

fn should_use_sudo_for(target_os: TargetOs, is_root: bool, upt_tool: Option<String>) -> bool {
    if is_root {
        return false;
    }
    if !target_os.is_linux() {
        return false;
    }

    let Some(tool) = upt_tool
        .as_deref()
        .map(str::trim)
        .filter(|tool| !tool.is_empty())
    else {
        return true;
    };

    !matches!(tool, "brew" | "mise" | "nix" | "nix-env")
}

#[cfg(unix)]
fn is_effective_root() -> bool {
    unsafe { libc::geteuid() == 0 }
}

#[cfg(not(unix))]
fn is_effective_root() -> bool {
    false
}

fn which_error_to_io(error: which::Error) -> std::io::Error {
    std::io::Error::new(std::io::ErrorKind::NotFound, error)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn linux_non_root_uses_sudo_by_default() {
        assert!(should_use_sudo_for(TargetOs::Ubuntu, false, None));
    }

    #[test]
    fn root_does_not_use_sudo() {
        assert!(!should_use_sudo_for(TargetOs::Ubuntu, true, None));
    }

    #[test]
    fn darwin_does_not_use_sudo_for_upt() {
        assert!(!should_use_sudo_for(TargetOs::Darwin, false, None));
    }

    #[test]
    fn brew_backend_skips_sudo() {
        assert!(!should_use_sudo_for(
            TargetOs::Linux,
            false,
            Some("brew".to_owned())
        ));
    }

    #[test]
    fn preview_shows_sudo_when_needed() {
        assert!(should_use_sudo_for(TargetOs::Ubuntu, false, None));
        let preview = format!("{}upt install -y cowsay", "sudo ");
        assert_eq!(preview, "sudo upt install -y cowsay");
    }
}
