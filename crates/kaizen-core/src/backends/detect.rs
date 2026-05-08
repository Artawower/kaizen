use crate::{
    backends::{NixSyncBackend, UptSyncBackend},
    SyncBackend, TargetOs,
};

/// Определяет подходящий бэкенд для текущей системы.
///
/// Приоритет: Nix (home-manager / darwin-rebuild) → upt
///
/// CLI и Tauri вызывают эту функцию — конкретный бэкенд скрыт.
pub fn detect_backend(os: TargetOs) -> Box<dyn SyncBackend> {
    if NixSyncBackend::new(os.clone()).is_available() {
        return Box::new(NixSyncBackend::new(os));
    }
    Box::new(UptSyncBackend::new(os))
}
