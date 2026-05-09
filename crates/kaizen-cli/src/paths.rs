use std::path::PathBuf;

use kaizen_core::PathProvider;

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
