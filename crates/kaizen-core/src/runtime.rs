use std::sync::Arc;

use crate::{chezmoi_client::ChezmoiClient, executor::ProcessExecutor, fs::FileSystem};

/// Shared runtime context injected into backends.
///
/// Holds all OS-level capabilities. Clone is cheap — all fields are Arc.
#[derive(Clone)]
pub struct Runtime {
    pub executor: Arc<dyn ProcessExecutor>,
    pub fs: Arc<dyn FileSystem>,
    pub chezmoi: Arc<dyn ChezmoiClient>,
}

impl Runtime {
    pub fn new(
        executor: Arc<dyn ProcessExecutor>,
        fs: Arc<dyn FileSystem>,
        chezmoi: Arc<dyn ChezmoiClient>,
    ) -> Self {
        Self {
            executor,
            fs,
            chezmoi,
        }
    }
}
