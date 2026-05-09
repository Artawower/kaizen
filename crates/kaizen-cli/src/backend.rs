use std::sync::Arc;

use kaizen_core::{NixSyncBackend, Runtime, StdFileSystem, StdPathProvider, SyncBackend, TargetOs, UptSyncBackend};

use crate::{
    chezmoi::StdChezmoiClient, docker::DockerCleaner, executor::StdProcessExecutor,
    installer::UptInstaller, mise::MiseToolchain,
};

/// Detect the appropriate sync backend for the current system.
///
/// All capability detection (`which`) lives here in CLI.
/// Injects all concrete adapters into the backend via Runtime.
pub fn detect_backend(os: TargetOs) -> Box<dyn SyncBackend> {
    let runtime = Runtime::new(
        Arc::new(StdProcessExecutor),
        Arc::new(StdFileSystem),
        Arc::new(StdChezmoiClient),
        Arc::new(StdPathProvider),
    );

    if nix_available() {
        return Box::new(NixSyncBackend::new(
            os,
            runtime,
            Box::new(MiseToolchain),
            Box::new(DockerCleaner),
        ));
    }
    Box::new(UptSyncBackend::new(
        os,
        runtime,
        Box::new(UptInstaller),
        Box::new(MiseToolchain),
        Box::new(DockerCleaner),
    ))
}

fn nix_available() -> bool {
    which::which("home-manager").is_ok() || which::which("darwin-rebuild").is_ok()
}
