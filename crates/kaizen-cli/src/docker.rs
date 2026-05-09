use kaizen_core::{
    container::ContainerCleaner,
    executor::{ProcessCommand, ProcessExecutor},
    KaizenError,
};

use crate::executor::StdProcessExecutor;

/// Concrete Docker-based container cleaner.
///
/// Lives in CLI, not core, because it calls `which::which` and spawns `docker`.
pub struct DockerCleaner;

impl ContainerCleaner for DockerCleaner {
    fn clean_step(&self) -> Option<String> {
        if which::which("docker").is_err() {
            return None;
        }
        Some("docker system prune -f".into())
    }

    fn clean(&self, dry_run: bool) -> Result<(), KaizenError> {
        if which::which("docker").is_err() || dry_run {
            return Ok(());
        }
        StdProcessExecutor.execute(ProcessCommand::run("docker", ["system", "prune", "-f"]))?;
        Ok(())
    }
}
