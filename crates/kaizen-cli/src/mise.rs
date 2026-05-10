use kaizen_core::{
    executor::{ProcessCommand, ProcessExecutor},
    toolchain::{DevToolsManager, ToolStep},
    KaizenError,
};

use crate::executor::StdProcessExecutor;

/// On macOS, collect extra env vars needed for `mise install` so that
/// cargo subprocesses can find system libraries like `libiconv`.
///
/// Sets `SDKROOT` (compiler headers) and prepends to `LIBRARY_PATH`
/// (link-time libs).  Both are needed because `cargo install` links with
/// `-nodefaultlibs`, which removes the default library search paths.
///
/// Also sets `PUPPETEER_SKIP_DOWNLOAD` so npm tools that embed Puppeteer
/// (e.g. mermaid-cli) do not try to download Chrome during `mise install`.
/// The caller is responsible for ensuring a suitable browser is available
/// at runtime (e.g. via Nix/brew Chromium package).
///
/// Returns an empty vec on non-macOS or when `xcrun` is unavailable.
fn macos_mise_env() -> Vec<(String, String)> {
    #[cfg(not(target_os = "macos"))]
    return vec![];

    #[cfg(target_os = "macos")]
    {
        let mut env = vec![("PUPPETEER_SKIP_DOWNLOAD".to_owned(), "true".to_owned())];

        let sdk = StdProcessExecutor
            .execute(
                ProcessCommand::run("xcrun", ["--sdk", "macosx", "--show-sdk-path"]).capturing(),
            )
            .ok()
            .map(|o| o.stdout);

        let Some(sdk) = sdk else {
            return env;
        };

        if std::env::var("SDKROOT").is_err() {
            env.push(("SDKROOT".to_owned(), sdk.clone()));
        }

        // Prepend the SDK lib path so the linker finds libiconv etc.
        let sdk_lib = format!("{sdk}/usr/lib");
        let lib_path = match std::env::var("LIBRARY_PATH") {
            Ok(existing) => format!("{sdk_lib}:{existing}"),
            Err(_) => sdk_lib,
        };
        env.push(("LIBRARY_PATH".to_owned(), lib_path));

        env
    }
}

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
        let mut cmd = ProcessCommand::run("mise", ["install"]);
        for (k, v) in macos_mise_env() {
            cmd = cmd.with_env(k, v);
        }
        StdProcessExecutor.execute(cmd)?;
        let mise_toml = dirs::home_dir()
            .ok_or(KaizenError::HomeDirUnavailable)?
            .join(".config/mise.toml");
        if mise_toml.exists() {
            let toml_str = mise_toml.to_string_lossy().into_owned();
            StdProcessExecutor.execute(ProcessCommand::run("mise", ["trust", &toml_str]))?;
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
        StdProcessExecutor.execute(ProcessCommand::run("mise", args))?;
        Ok(())
    }
}
