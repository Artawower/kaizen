use crate::KaizenError;

pub trait Installer {
    fn install(&self, programs: &[String]) -> Result<(), KaizenError>;
    fn preview(&self, programs: &[String]) -> String;
}

pub struct UptInstaller;

impl Installer for UptInstaller {
    fn install(&self, programs: &[String]) -> Result<(), KaizenError> {
        if programs.is_empty() {
            return Ok(());
        }
        let status = std::process::Command::new("upt")
            .arg("install")
            .args(programs)
            .status()?;

        if status.success() {
            return Ok(());
        }
        Err(KaizenError::InstallerFailed {
            installer: "upt",
            code: status.code(),
        })
    }

    fn preview(&self, programs: &[String]) -> String {
        format!("upt install {}", programs.join(" "))
    }
}
