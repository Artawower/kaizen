use std::sync::Arc;

use kaizen_core::{
    NixSyncBackend, PackageManagerKind, Runtime, SyncBackend, TargetOs, UptSyncBackend,
};

use crate::{
    chezmoi::StdChezmoiClient, docker::DockerCleaner, executor::StdProcessExecutor,
    filesystem::StdFileSystem, installer::UptInstaller, mise::MiseToolchain,
    paths::StdPathProvider,
};

/// Detect the appropriate sync backend for the current system.
///
/// All capability detection (`which`) lives here in CLI.
/// Injects all concrete adapters into the backend via Runtime.
pub fn detect_backend(os: TargetOs) -> Box<dyn SyncBackend> {
    let pm = detect_pm(&os);
    let runtime = Runtime::new(
        Arc::new(StdProcessExecutor),
        Arc::new(StdFileSystem),
        Arc::new(StdChezmoiClient),
        Arc::new(StdPathProvider),
        pm,
    );

    if nix_available() {
        return Box::new(NixSyncBackend::new(
            os,
            runtime,
            Box::new(MiseToolchain),
            Box::new(DockerCleaner),
        ));
    }
    Box::new(UptSyncBackend::new(
        os,
        runtime,
        Box::new(UptInstaller),
        Box::new(MiseToolchain),
        Box::new(DockerCleaner),
    ))
}

/// Detect the package manager for the current OS using `which`.
/// This belongs in CLI because it queries the running system via PATH.
fn detect_pm(os: &TargetOs) -> PackageManagerKind {
    match os {
        TargetOs::Darwin => PackageManagerKind::Brew,
        TargetOs::Fedora => PackageManagerKind::Dnf,
        TargetOs::Ubuntu => PackageManagerKind::Apt,
        TargetOs::Linux => detect_generic_linux_pm(),
        _ => PackageManagerKind::Unknown,
    }
}

fn detect_generic_linux_pm() -> PackageManagerKind {
    [
        ("dnf", PackageManagerKind::Dnf),
        ("apt", PackageManagerKind::Apt),
        ("pacman", PackageManagerKind::Pacman),
    ]
    .into_iter()
    .find(|(bin, _)| which::which(bin).is_ok())
    .map(|(_, kind)| kind)
    .unwrap_or(PackageManagerKind::Unknown)
}

fn nix_available() -> bool {
    which::which("home-manager").is_ok() || which::which("darwin-rebuild").is_ok()
}
