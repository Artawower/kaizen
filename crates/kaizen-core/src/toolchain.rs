use crate::KaizenError;

/// A single labelled step shown in dry-run / preview output.
#[derive(Debug, Clone)]
pub struct ToolStep {
    pub label: String,
    pub command: String,
}

/// Port for dev-toolchain management (mise or equivalent).
///
/// Concrete implementation (`MiseToolchain`) lives in kaizen-cli.
/// Core backends receive this via constructor injection.
pub trait DevToolsManager: Send + Sync {
    /// Preview step to show during dry-run; `None` when the tool is unavailable.
    fn install_step(&self) -> Option<ToolStep>;

    /// Run `mise install` (and related setup). No-op when dry_run.
    fn install(&self, dry_run: bool) -> Result<(), KaizenError>;

    /// Run `mise upgrade <tools>`. No-op when dry_run or tool list is empty.
    fn upgrade(&self, tools: &[String], dry_run: bool) -> Result<(), KaizenError>;
}

/// No-op implementation for tests and headless contexts without mise.
pub struct NoopDevTools;

impl DevToolsManager for NoopDevTools {
    fn install_step(&self) -> Option<ToolStep> {
        None
    }
    fn install(&self, _dry_run: bool) -> Result<(), KaizenError> {
        Ok(())
    }
    fn upgrade(&self, _tools: &[String], _dry_run: bool) -> Result<(), KaizenError> {
        Ok(())
    }
}
