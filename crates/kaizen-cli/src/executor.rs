use kaizen_core::{
    executor::{ProcessCommand, ProcessExecutor, ProcessOutput},
    KaizenError,
};

/// Concrete process executor using `std::process::Command`.
///
/// Lives in CLI, not core, because it spawns real OS processes.
pub struct StdProcessExecutor;

impl ProcessExecutor for StdProcessExecutor {
    fn execute(&self, cmd: ProcessCommand) -> Result<ProcessOutput, KaizenError> {
        match (cmd.sudo, cmd.capture_stdout) {
            (true, true) => run_sudo_capturing(cmd),
            (true, false) => run_sudo(cmd),
            (false, true) => run_capturing(cmd),
            (false, false) => run_status(cmd),
        }
    }
}

/// Build the PATH string for a command with `path_prefix` set.
/// Returns `None` when the prefix list is empty (no override needed).
fn effective_path(cmd: &ProcessCommand) -> Option<String> {
    if cmd.path_prefix.is_empty() {
        return None;
    }
    let current = std::env::var("PATH").unwrap_or_default();
    let prefix = cmd.path_prefix.join(":");
    Some(format!("{prefix}:{current}"))
}

/// Create a `std::process::Command` for a non-sudo invocation,
/// applying the PATH prefix when present.
fn base_command(cmd: &ProcessCommand) -> std::process::Command {
    let mut c = std::process::Command::new(&cmd.bin);
    c.args(&cmd.args);
    if let Some(path) = effective_path(cmd) {
        c.env("PATH", path);
    }
    for (k, v) in &cmd.env {
        c.env(k, v);
    }
    c
}

/// Create a `std::process::Command` for a sudo invocation.
///
/// Uses `sudo env PATH=… <bin> args` so that PATH survives sudo's
/// `secure_path` stripping and the child process can find nix tools.
#[allow(clippy::result_large_err)]
fn sudo_command(cmd: &ProcessCommand) -> Result<std::process::Command, KaizenError> {
    // Resolve binary against the effective PATH (prefix + current), not just the
    // current process PATH. `nix` may only be in nix_path_prefix and absent from
    // the shell PATH on a fresh install or in a restricted environment.
    let path_val = effective_path(cmd).unwrap_or_else(|| std::env::var("PATH").unwrap_or_default());
    let bin_path = which::which_in(&cmd.bin, Some(&path_val), std::env::current_dir()?)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::NotFound, e))?;

    let mut c = std::process::Command::new("sudo");
    c.arg("-p").arg("[kaizen] sudo password: ");
    c.arg("env");
    // Pass PATH explicitly so sudo child inherits nix profile dirs.
    c.arg(format!("PATH={path_val}"));
    // Forward extra env vars so they survive sudo's secure_path stripping.
    for (k, v) in &cmd.env {
        c.arg(format!("{k}={v}"));
    }
    c.arg(bin_path).args(&cmd.args);
    Ok(c)
}

#[allow(clippy::result_large_err)]
fn run_status(cmd: ProcessCommand) -> Result<ProcessOutput, KaizenError> {
    let status = base_command(&cmd).status()?;
    if !status.success() {
        return Err(KaizenError::CommandFailed {
            cmd: cmd_label(&cmd),
            code: status.code(),
        });
    }
    Ok(ProcessOutput::default())
}

#[allow(clippy::result_large_err)]
fn run_sudo(cmd: ProcessCommand) -> Result<ProcessOutput, KaizenError> {
    let status = sudo_command(&cmd)?.status()?;
    if !status.success() {
        return Err(KaizenError::CommandFailed {
            cmd: format!("sudo {}", cmd_label(&cmd)),
            code: status.code(),
        });
    }
    Ok(ProcessOutput::default())
}

#[allow(clippy::result_large_err)]
fn run_capturing(cmd: ProcessCommand) -> Result<ProcessOutput, KaizenError> {
    let out = base_command(&cmd).output()?;
    if !out.status.success() {
        return Err(KaizenError::CommandFailed {
            cmd: cmd_label(&cmd),
            code: out.status.code(),
        });
    }
    Ok(ProcessOutput {
        stdout: String::from_utf8_lossy(&out.stdout).trim().to_owned(),
    })
}

#[allow(clippy::result_large_err)]
fn run_sudo_capturing(cmd: ProcessCommand) -> Result<ProcessOutput, KaizenError> {
    let out = sudo_command(&cmd)?.output()?;
    if !out.status.success() {
        return Err(KaizenError::CommandFailed {
            cmd: format!("sudo {}", cmd_label(&cmd)),
            code: out.status.code(),
        });
    }
    Ok(ProcessOutput {
        stdout: String::from_utf8_lossy(&out.stdout).trim().to_owned(),
    })
}

fn cmd_label(cmd: &ProcessCommand) -> String {
    if cmd.args.is_empty() {
        cmd.bin.clone()
    } else {
        format!("{} {}", cmd.bin, cmd.args.join(" "))
    }
}
