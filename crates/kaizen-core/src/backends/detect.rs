use crate::{
    backends::{NixSyncBackend, UptSyncBackend},
    SyncBackend, TargetOs,
};

/// Detect the appropriate sync backend for the current system.
/// Priority: Nix (home-manager / darwin-rebuild) → upt
pub fn detect_backend(os: TargetOs) -> Box<dyn SyncBackend> {
    let nix = NixSyncBackend::new(os.clone());
    if nix.is_available() {
        return Box::new(nix);
    }
    Box::new(UptSyncBackend::new(os))
}
