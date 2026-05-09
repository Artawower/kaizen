use std::path::PathBuf;

/// Port for platform-specific directory resolution.
///
/// Abstracts `dirs::home_dir()` / `dirs::config_dir()` so that backends
/// can be tested without depending on the real user home directory.
pub trait PathProvider: Send + Sync {
    fn home_dir(&self) -> Option<PathBuf>;
    fn config_dir(&self) -> Option<PathBuf>;
    /// Check whether `tool` is on PATH. Used by backend cleanup to skip unavailable tools.
    fn is_tool_available(&self, tool: &str) -> bool;
}

/// Standard implementation backed by the `dirs` crate.
pub struct StdPathProvider;

impl PathProvider for StdPathProvider {
    fn home_dir(&self) -> Option<PathBuf> {
        dirs::home_dir()
    }

    fn config_dir(&self) -> Option<PathBuf> {
        dirs::config_dir().or_else(|| dirs::home_dir().map(|h| h.join(".config")))
    }

    fn is_tool_available(&self, tool: &str) -> bool {
        which::which(tool).is_ok()
    }
}
