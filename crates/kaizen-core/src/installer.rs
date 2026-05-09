use crate::KaizenError;

pub trait Installer: Send + Sync {
    fn install(&self, programs: &[String]) -> Result<(), KaizenError>;
    fn preview_install(&self, programs: &[String]) -> String;
}

pub trait Updater: Send + Sync {
    fn upgrade(&self, programs: &[String]) -> Result<(), KaizenError>;
    fn preview_upgrade(&self, programs: &[String]) -> String;
}

pub trait Remover: Send + Sync {
    fn remove(&self, programs: &[String]) -> Result<(), KaizenError>;
    fn preview_remove(&self, programs: &[String]) -> String;
}

/// Combined trait for backends that need install + upgrade capabilities.
///
/// Implement this on any concrete package manager adapter (e.g. `UptInstaller` in CLI).
pub trait PackageInstaller: Installer + Updater {}
impl<T: Installer + Updater> PackageInstaller for T {}
