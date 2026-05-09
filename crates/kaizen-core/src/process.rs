use std::process::{Command, Stdio};

use crate::KaizenError;

/// Run a command, inheriting stdin/stdout/stderr. Return error on non-zero exit.
pub fn run_cmd(bin: &str, args: &[&str]) -> Result<(), KaizenError> {
    let status = Command::new(bin).args(args).status()?;
    if !status.success() {
        return Err(KaizenError::CommandFailed {
            cmd: cmd_label(bin, args),
            code: status.code(),
        });
    }
    Ok(())
}

/// Run a command with `sudo`, inheriting stdin/stdout/stderr.
pub fn run_cmd_sudo(bin: &str, args: &[&str]) -> Result<(), KaizenError> {
    let mut sudo_args = vec![bin];
    sudo_args.extend_from_slice(args);
    let status = Command::new("sudo").args(&sudo_args).status()?;
    if !status.success() {
        return Err(KaizenError::CommandFailed {
            cmd: format!("sudo {}", cmd_label(bin, args)),
            code: status.code(),
        });
    }
    Ok(())
}

/// Run a command, capture stdout, inherit stderr. Return trimmed stdout on success.
pub fn run_cmd_output(bin: &str, args: &[&str]) -> Result<String, KaizenError> {
    let out = Command::new(bin).args(args).output()?;
    if !out.status.success() {
        return Err(KaizenError::CommandFailed {
            cmd: cmd_label(bin, args),
            code: out.status.code(),
        });
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_owned())
}

/// Run a command, capture stderr for error reporting, inherit stdout.
/// Returns captured stderr on failure for inclusion in error messages.
pub fn run_cmd_capture_stderr(bin: &str, args: &[&str]) -> Result<(), CapturedStderrError> {
    use std::io::Read;

    let mut child = Command::new(bin)
        .args(args)
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| CapturedStderrError {
            cmd: cmd_label(bin, args),
            code: None,
            stderr: e.to_string(),
        })?;

    let stderr_bytes = child
        .stderr
        .take()
        .map(|mut s| {
            let mut buf = Vec::new();
            let _ = s.read_to_end(&mut buf);
            buf
        })
        .unwrap_or_default();

    let status = child.wait().map_err(|e| CapturedStderrError {
        cmd: cmd_label(bin, args),
        code: None,
        stderr: e.to_string(),
    })?;

    if !status.success() {
        return Err(CapturedStderrError {
            cmd: cmd_label(bin, args),
            code: status.code(),
            stderr: String::from_utf8_lossy(&stderr_bytes).trim().to_owned(),
        });
    }
    Ok(())
}

/// Error returned by `run_cmd_capture_stderr` containing the captured stderr.
#[derive(Debug)]
pub struct CapturedStderrError {
    pub cmd: String,
    pub code: Option<i32>,
    pub stderr: String,
}

/// Run only if the binary is available in PATH. Silently skip if not found.
pub fn run_cmd_if_available(bin: &str, args: &[&str]) -> Result<(), KaizenError> {
    if which::which(bin).is_err() {
        return Ok(());
    }
    run_cmd(bin, args)
}

fn cmd_label(bin: &str, args: &[&str]) -> String {
    if args.is_empty() {
        bin.to_owned()
    } else {
        format!("{bin} {}", args.join(" "))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cmd_label_no_args() {
        assert_eq!(cmd_label("nix", &[]), "nix");
    }

    #[test]
    fn cmd_label_with_args() {
        assert_eq!(cmd_label("nix", &["flake", "update"]), "nix flake update");
    }

    #[test]
    fn run_cmd_true_succeeds() {
        assert!(run_cmd("true", &[]).is_ok());
    }

    #[test]
    fn run_cmd_false_returns_error() {
        let err = run_cmd("false", &[]).unwrap_err();
        assert!(matches!(err, KaizenError::CommandFailed { .. }));
    }

    #[test]
    fn run_cmd_output_captures_stdout() {
        let out = run_cmd_output("echo", &["hello"]).unwrap();
        assert_eq!(out, "hello");
    }

    #[test]
    fn run_cmd_output_fails_on_nonzero() {
        assert!(run_cmd_output("false", &[]).is_err());
    }

    #[test]
    fn run_cmd_if_available_skips_missing_binary() {
        assert!(run_cmd_if_available("__nonexistent_binary__", &[]).is_ok());
    }
}
