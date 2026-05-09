use kaizen_core::{container::ContainerCleaner, process, KaizenError};

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
        process::run_cmd("docker", &["system", "prune", "-f"])
    }
}
