use crate::KaizenError;

/// Port for container runtime cleanup (docker or equivalent).
///
/// Concrete implementation (`DockerCleaner`) lives in kaizen-cli.
/// Core backends receive this via constructor injection.
pub trait ContainerCleaner: Send + Sync {
    /// Preview step string; `None` when the runtime is unavailable.
    fn clean_step(&self) -> Option<String>;

    /// Run container cleanup. No-op when dry_run.
    fn clean(&self, dry_run: bool) -> Result<(), KaizenError>;
}

/// No-op implementation for tests and headless contexts without docker.
pub struct NoopContainerCleaner;

impl ContainerCleaner for NoopContainerCleaner {
    fn clean_step(&self) -> Option<String> {
        None
    }
    fn clean(&self, _dry_run: bool) -> Result<(), KaizenError> {
        Ok(())
    }
}
