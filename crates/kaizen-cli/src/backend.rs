use kaizen_core::{NixSyncBackend, SyncBackend, TargetOs, UptSyncBackend};

use crate::installer::UptInstaller;

/// Detect the appropriate sync backend for the current system.
///
/// Lives in CLI (not core) because `UptSyncBackend` requires a concrete `UptInstaller`
/// that spawns OS processes — a CLI-layer concern.
///
/// Priority: Nix (home-manager / darwin-rebuild) → upt
pub fn detect_backend(os: TargetOs) -> Box<dyn SyncBackend> {
    let nix = NixSyncBackend::new(os.clone());
    if nix.is_available() {
        return Box::new(nix);
    }
    Box::new(UptSyncBackend::new(os, Box::new(UptInstaller)))
}
