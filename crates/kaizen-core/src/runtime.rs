use std::sync::Arc;

use crate::{
    chezmoi_client::ChezmoiClient, executor::ProcessExecutor, fs::FileSystem,
    os::PackageManagerKind, paths::PathProvider,
};

/// Shared runtime context injected into backends.
///
/// Holds all OS-level capabilities. Clone is cheap — all fields are Arc.
#[derive(Clone)]
pub struct Runtime {
    pub executor: Arc<dyn ProcessExecutor>,
    pub fs: Arc<dyn FileSystem>,
    pub chezmoi: Arc<dyn ChezmoiClient>,
    pub paths: Arc<dyn PathProvider>,
    /// Package manager for the current OS — detected by CLI (requires `which`).
    pub pm: PackageManagerKind,
}

impl Runtime {
    pub fn new(
        executor: Arc<dyn ProcessExecutor>,
        fs: Arc<dyn FileSystem>,
        chezmoi: Arc<dyn ChezmoiClient>,
        paths: Arc<dyn PathProvider>,
        pm: PackageManagerKind,
    ) -> Self {
        Self {
            executor,
            fs,
            chezmoi,
            paths,
            pm,
        }
    }
}
