use std::sync::Arc;

use crate::{executor::ProcessExecutor, fs::FileSystem};

/// Shared runtime context injected into backends.
///
/// Holds all OS-level capabilities. Clone is cheap — all fields are Arc.
#[derive(Clone)]
pub struct Runtime {
    pub executor: Arc<dyn ProcessExecutor>,
    pub fs: Arc<dyn FileSystem>,
}

impl Runtime {
    pub fn new(executor: Arc<dyn ProcessExecutor>, fs: Arc<dyn FileSystem>) -> Self {
        Self { executor, fs }
    }
}
