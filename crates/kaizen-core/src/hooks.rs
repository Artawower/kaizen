use crate::KaizenError;

pub trait HookRunner {
    fn run(&self, commands: &[String]) -> Result<(), KaizenError>;
}

pub struct ShellHookRunner;

impl HookRunner for ShellHookRunner {
    fn run(&self, commands: &[String]) -> Result<(), KaizenError> {
        for cmd in commands {
            let status = std::process::Command::new("sh")
                .arg("-c")
                .arg(cmd)
                .status()
                .map_err(|e| KaizenError::HookFailed {
                    command: cmd.clone(),
                    reason: e.to_string(),
                })?;

            if !status.success() {
                return Err(KaizenError::HookFailed {
                    command: cmd.clone(),
                    reason: format!(
                        "exited with {}",
                        status
                            .code()
                            .map(|c| c.to_string())
                            .unwrap_or_else(|| "signal".to_owned())
                    ),
                });
            }
        }
        Ok(())
    }
}
