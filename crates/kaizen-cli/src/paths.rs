use std::path::PathBuf;

use kaizen_core::PathProvider;

pub struct StdPathProvider;

impl PathProvider for StdPathProvider {
    fn home_dir(&self) -> Option<PathBuf> {
        dirs::home_dir()
    }

    fn config_dir(&self) -> Option<PathBuf> {
        // Always use XDG-style ~/.config — kaizen is XDG-based even on macOS.
        // dirs::config_dir() returns ~/Library/Application Support on macOS,
        // which is wrong for Nix, mise, and kaizen's own config.
        dirs::home_dir().map(|h| h.join(".config"))
    }

    fn is_tool_available(&self, tool: &str) -> bool {
        which::which(tool).is_ok()
    }
}
