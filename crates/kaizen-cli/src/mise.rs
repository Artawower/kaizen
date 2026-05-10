use kaizen_core::{
    executor::{ProcessCommand, ProcessExecutor},
    toolchain::{DevToolsManager, ToolStep},
    KaizenError,
};

use crate::executor::StdProcessExecutor;

/// Environment variables that guarantee a successful `mise install` regardless
/// of what the user's shell PATH looks like.
///
/// **Invariant (macOS):** C/C++ compilation inside cargo subprocesses always
/// uses Apple's toolchain with the current system SDK.  This prevents failures
/// caused by Nix-provided clang (which does not translate `SDKROOT` into
/// `-isysroot` the way Apple's `/usr/bin/cc` shim does).
///
/// New entries belong here only if they protect this invariant or the
/// analogous cross-platform bootstrap guarantee below.  Per-crate workarounds
/// (feature flags, crate-specific env vars) do NOT belong here.
fn macos_compile_env() -> Vec<(String, String)> {
    #[cfg(not(target_os = "macos"))]
    return vec![];

    #[cfg(target_os = "macos")]
    {
        let sdk = StdProcessExecutor
            .execute(
                ProcessCommand::run("xcrun", ["--sdk", "macosx", "--show-sdk-path"]).capturing(),
            )
            .ok()
            .map(|o| o.stdout);

        let Some(sdk) = sdk else {
            return vec![];
        };

        let mut env = vec![];

        // Force Apple toolchain so cc-rs picks up the correct sysroot.
        // /usr/bin/cc is the xcrun shim: it automatically selects the active
        // SDK and adds -isysroot, which Nix clang does not do.
        if std::path::Path::new("/usr/bin/cc").exists() {
            env.push(("CC".to_owned(), "/usr/bin/cc".to_owned()));
            env.push(("CXX".to_owned(), "/usr/bin/c++".to_owned()));
        }

        if std::env::var("SDKROOT").is_err() {
            env.push(("SDKROOT".to_owned(), sdk.clone()));
        }

        // Prepend SDK lib path so the linker finds libiconv etc.
        // cargo links with -nodefaultlibs which removes standard search paths.
        let sdk_lib = format!("{sdk}/usr/lib");
        let lib_path = match std::env::var("LIBRARY_PATH") {
            Ok(existing) => format!("{sdk_lib}:{existing}"),
            Err(_) => sdk_lib,
        };
        env.push(("LIBRARY_PATH".to_owned(), lib_path));

        env
    }
}

/// Cross-platform env vars that prevent `mise install` from making
/// network downloads for optional browser/headless runtimes.
///
/// Tools like `@mermaid-js/mermaid-cli` embed Puppeteer which tries to
/// download Chrome on `npm install`.  Kaizen does not manage browsers;
/// they must be provided by the system package layer (Nix / brew).
fn mise_no_download_env() -> Vec<(String, String)> {
    vec![("PUPPETEER_SKIP_DOWNLOAD".to_owned(), "true".to_owned())]
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
        for (k, v) in macos_compile_env()
            .into_iter()
            .chain(mise_no_download_env())
        {
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
