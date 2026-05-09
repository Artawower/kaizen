use kaizen_core::{NixSyncBackend, SyncBackend, TargetOs, UptSyncBackend};

use crate::{docker::DockerCleaner, installer::UptInstaller, mise::MiseToolchain};

/// Detect the appropriate sync backend for the current system.
///
/// All capability detection (`which`) lives here in CLI, not in core.
/// Priority: Nix (home-manager / darwin-rebuild) → upt
pub fn detect_backend(os: TargetOs) -> Box<dyn SyncBackend> {
    if nix_available() {
        return Box::new(NixSyncBackend::new(
            os,
            Box::new(MiseToolchain),
            Box::new(DockerCleaner),
        ));
    }
    Box::new(UptSyncBackend::new(
        os,
        Box::new(UptInstaller),
        Box::new(MiseToolchain),
        Box::new(DockerCleaner),
    ))
}

fn nix_available() -> bool {
    which::which("home-manager").is_ok() || which::which("darwin-rebuild").is_ok()
}
