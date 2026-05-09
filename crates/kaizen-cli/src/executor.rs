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

#[allow(clippy::result_large_err)]
fn run_status(cmd: ProcessCommand) -> Result<ProcessOutput, KaizenError> {
    let status = std::process::Command::new(&cmd.bin)
        .args(&cmd.args)
        .status()?;
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
    let bin_path = which::which(&cmd.bin)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::NotFound, e))?;
    let status = std::process::Command::new("sudo")
        .arg("-p")
        .arg("[kaizen] sudo password: ")
        .arg(bin_path)
        .args(&cmd.args)
        .status()?;
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
    let out = std::process::Command::new(&cmd.bin)
        .args(&cmd.args)
        .output()?;
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
    let bin_path = which::which(&cmd.bin)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::NotFound, e))?;
    let out = std::process::Command::new("sudo")
        .arg("-p")
        .arg("[kaizen] sudo password: ")
        .arg(bin_path)
        .args(&cmd.args)
        .output()?;
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
