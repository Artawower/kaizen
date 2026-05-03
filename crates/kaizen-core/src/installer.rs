use crate::KaizenError;

pub trait Installer {
    fn install(&self, programs: &[String]) -> Result<(), KaizenError>;
    fn preview_install(&self, programs: &[String]) -> String;
}

pub trait Remover {
    fn remove(&self, programs: &[String]) -> Result<(), KaizenError>;
    fn preview_remove(&self, programs: &[String]) -> String;
}

pub struct UptInstaller;

impl Installer for UptInstaller {
    fn install(&self, programs: &[String]) -> Result<(), KaizenError> {
        run_upt(&["install"], programs)
    }

    fn preview_install(&self, programs: &[String]) -> String {
        format!("upt install {}", programs.join(" "))
    }
}

impl Remover for UptInstaller {
    fn remove(&self, programs: &[String]) -> Result<(), KaizenError> {
        run_upt(&["remove"], programs)
    }

    fn preview_remove(&self, programs: &[String]) -> String {
        format!("upt remove {}", programs.join(" "))
    }
}

fn run_upt(args: &[&str], programs: &[String]) -> Result<(), KaizenError> {
    let mut failed: Vec<String> = Vec::new();
    for program in programs {
        let status = std::process::Command::new("upt")
            .args(args)
            .arg(program)
            .status()?;
        if !status.success() {
            failed.push(program.clone());
        }
    }
    if failed.is_empty() {
        return Ok(());
    }
    Err(KaizenError::InstallerPartialFailure {
        count: failed.len(),
        failed,
    })
}
