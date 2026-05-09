use kaizen_core::{
    process,
    toolchain::{DevToolsManager, ToolStep},
    KaizenError,
};

/// Concrete mise-based dev toolchain manager.
///
/// Lives in CLI, not core, because it calls `which::which` and spawns `mise`.
pub struct MiseToolchain;

impl DevToolsManager for MiseToolchain {
    fn install_step(&self) -> Option<ToolStep> {
        if which::which("mise").is_err() {
            return None;
        }
        Some(ToolStep {
            label: "install mise tools".into(),
            command: "mise install".into(),
        })
    }

    fn install(&self, dry_run: bool) -> Result<(), KaizenError> {
        if which::which("mise").is_err() || dry_run {
            return Ok(());
        }
        process::run_cmd("mise", &["install"])?;
        let mise_toml = dirs::home_dir()
            .ok_or(KaizenError::HomeDirUnavailable)?
            .join(".config/mise.toml");
        if mise_toml.exists() {
            let toml_str = mise_toml.to_string_lossy().into_owned();
            process::run_cmd("mise", &["trust", &toml_str])?;
        }
        Ok(())
    }

    fn upgrade(&self, tools: &[String], dry_run: bool) -> Result<(), KaizenError> {
        if which::which("mise").is_err() || dry_run || tools.is_empty() {
            return Ok(());
        }
        let tool_refs: Vec<&str> = tools.iter().map(String::as_str).collect();
        let mut args = vec!["upgrade"];
        args.extend_from_slice(&tool_refs);
        process::run_cmd("mise", &args)
    }
}
