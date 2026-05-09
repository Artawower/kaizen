use crate::KaizenError;

/// Describes how to run a process and what output to capture.
#[derive(Debug, Clone)]
pub struct ProcessCommand {
    pub bin: String,
    pub args: Vec<String>,
    pub sudo: bool,
    pub capture_stdout: bool,
}

impl ProcessCommand {
    /// Run a command, inheriting stdin/stdout/stderr.
    pub fn run(bin: impl Into<String>, args: impl IntoIterator<Item = impl Into<String>>) -> Self {
        Self {
            bin: bin.into(),
            args: args.into_iter().map(Into::into).collect(),
            sudo: false,
            capture_stdout: false,
        }
    }

    /// Wrap the command with `sudo`.
    pub fn sudo(mut self) -> Self {
        self.sudo = true;
        self
    }

    /// Capture stdout instead of inheriting it.
    pub fn capturing(mut self) -> Self {
        self.capture_stdout = true;
        self
    }
}

/// Output returned by a successful `ProcessExecutor::execute` call.
#[derive(Debug, Default)]
pub struct ProcessOutput {
    /// Captured stdout (only populated when `capture_stdout = true`).
    pub stdout: String,
}

/// Port for running OS processes.
///
/// Concrete implementation (`StdProcessExecutor`) lives in kaizen-cli.
/// Core logic receives this via `Runtime` injection.
pub trait ProcessExecutor: Send + Sync {
    /// Execute the command and return its output.
    ///
    /// Returns `Err` on non-zero exit code.
    fn execute(&self, cmd: ProcessCommand) -> Result<ProcessOutput, KaizenError>;
}

/// No-op executor: succeeds silently without spawning anything.
/// Used in dry-run tests where commands must not actually run.
pub struct NoopExecutor;

impl ProcessExecutor for NoopExecutor {
    fn execute(&self, _cmd: ProcessCommand) -> Result<ProcessOutput, KaizenError> {
        Ok(ProcessOutput::default())
    }
}

/// Recording executor: captures all commands for assertion in tests.
#[cfg(test)]
pub struct RecordingExecutor {
    calls: std::sync::Mutex<Vec<ProcessCommand>>,
}

#[cfg(test)]
impl RecordingExecutor {
    pub fn new() -> Self {
        Self {
            calls: std::sync::Mutex::new(vec![]),
        }
    }

    pub fn calls(&self) -> Vec<ProcessCommand> {
        self.calls.lock().unwrap().clone()
    }

    pub fn was_called_with(&self, bin: &str) -> bool {
        self.calls.lock().unwrap().iter().any(|c| c.bin == bin)
    }
}

#[cfg(test)]
impl ProcessExecutor for RecordingExecutor {
    fn execute(&self, cmd: ProcessCommand) -> Result<ProcessOutput, KaizenError> {
        self.calls.lock().unwrap().push(cmd);
        Ok(ProcessOutput::default())
    }
}
