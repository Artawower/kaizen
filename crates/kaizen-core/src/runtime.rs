use std::sync::Arc;

use crate::executor::ProcessExecutor;

/// Shared runtime context injected into backends.
///
/// Holds all OS-level capabilities (process execution, filesystem, etc.).
/// Clone is cheap — all fields are reference-counted.
#[derive(Clone)]
pub struct Runtime {
    pub executor: Arc<dyn ProcessExecutor>,
}

impl Runtime {
    pub fn new(executor: Arc<dyn ProcessExecutor>) -> Self {
        Self { executor }
    }
}
