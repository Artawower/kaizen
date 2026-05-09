use std::path::PathBuf;

/// Port for platform-specific directory resolution.
///
/// Abstracts `dirs::home_dir()` / `dirs::config_dir()` so that backends
/// can be tested without depending on the real user home directory.
pub trait PathProvider: Send + Sync {
    fn home_dir(&self) -> Option<PathBuf>;
    fn config_dir(&self) -> Option<PathBuf>;
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
}
