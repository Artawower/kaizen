use os_info::Type;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PackageManagerKind {
    Brew,
    Dnf,
    Apt,
    Pacman,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TargetOs {
    Darwin,
    Fedora,
    Ubuntu,
    Linux,
    Unknown(String),
}

impl TargetOs {
    pub fn detect() -> Self {
        Self::from(os_info::get().os_type())
    }

    pub fn section_keys(&self) -> Vec<&'static str> {
        match self {
            TargetOs::Darwin => vec!["darwin"],
            TargetOs::Fedora => vec!["linux", "fedora"],
            TargetOs::Ubuntu => vec!["linux", "ubuntu"],
            TargetOs::Linux => vec!["linux"],
            TargetOs::Unknown(_) => vec![],
        }
    }

    pub fn as_str(&self) -> &str {
        match self {
            TargetOs::Darwin => "darwin",
            TargetOs::Fedora => "fedora",
            TargetOs::Ubuntu => "ubuntu",
            TargetOs::Linux => "linux",
            TargetOs::Unknown(s) => s.as_str(),
        }
    }

    /// Broad platform family for variant `platforms` matching.
    /// Maps all Linux distros to `"linux"` so `platforms = ["linux"]` covers Fedora, Ubuntu, etc.
    pub fn platform_family(&self) -> &str {
        match self {
            TargetOs::Darwin => "darwin",
            TargetOs::Fedora | TargetOs::Ubuntu | TargetOs::Linux => "linux",
            TargetOs::Unknown(_) => "unknown",
        }
    }

    pub fn is_linux(&self) -> bool {
        matches!(self, TargetOs::Fedora | TargetOs::Ubuntu | TargetOs::Linux)
    }

    /// Returns the package manager for well-known OS variants.
    /// For generic `TargetOs::Linux`, returns `Unknown` — detection requires
    /// `which` and belongs in the CLI layer (see `kaizen_cli::backend::detect_pm`).
    pub fn package_manager_kind(&self) -> PackageManagerKind {
        match self {
            TargetOs::Darwin => PackageManagerKind::Brew,
            TargetOs::Fedora => PackageManagerKind::Dnf,
            TargetOs::Ubuntu => PackageManagerKind::Apt,
            TargetOs::Linux | TargetOs::Unknown(_) => PackageManagerKind::Unknown,
        }
    }
}

impl From<os_info::Type> for TargetOs {
    fn from(t: os_info::Type) -> Self {
        match t {
            Type::Macos => TargetOs::Darwin,
            Type::Fedora => TargetOs::Fedora,
            Type::Ubuntu => TargetOs::Ubuntu,
            Type::Windows
            | Type::FreeBSD
            | Type::NetBSD
            | Type::OpenBSD
            | Type::DragonFly
            | Type::HardenedBSD
            | Type::MidnightBSD
            | Type::Illumos
            | Type::Android
            | Type::Ios
            | Type::Emscripten
            | Type::Redox
            | Type::Cygwin
            | Type::Unknown => TargetOs::Unknown(t.to_string().to_lowercase()),
            _ => TargetOs::Linux,
        }
    }
}

impl std::fmt::Display for TargetOs {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_macos() {
        assert_eq!(TargetOs::from(Type::Macos), TargetOs::Darwin);
    }
    #[test]
    fn maps_fedora() {
        assert_eq!(TargetOs::from(Type::Fedora), TargetOs::Fedora);
    }
    #[test]
    fn maps_ubuntu() {
        assert_eq!(TargetOs::from(Type::Ubuntu), TargetOs::Ubuntu);
    }
    #[test]
    fn maps_arch_to_linux() {
        assert_eq!(TargetOs::from(Type::Arch), TargetOs::Linux);
    }
    #[test]
    fn maps_nixos_to_linux() {
        assert_eq!(TargetOs::from(Type::NixOS), TargetOs::Linux);
    }
    #[test]
    fn maps_nobara_to_linux() {
        assert_eq!(TargetOs::from(Type::Nobara), TargetOs::Linux);
    }
    #[test]
    fn maps_alma_to_linux() {
        assert_eq!(TargetOs::from(Type::AlmaLinux), TargetOs::Linux);
    }
    #[test]
    fn maps_rocky_to_linux() {
        assert_eq!(TargetOs::from(Type::RockyLinux), TargetOs::Linux);
    }
    #[test]
    fn maps_freebsd_to_unknown() {
        assert!(matches!(
            TargetOs::from(Type::FreeBSD),
            TargetOs::Unknown(_)
        ));
    }
    #[test]
    fn maps_unknown_to_unknown() {
        assert!(matches!(
            TargetOs::from(Type::Unknown),
            TargetOs::Unknown(_)
        ));
    }
    #[test]
    fn fedora_section_keys_include_linux() {
        assert_eq!(TargetOs::Fedora.section_keys(), vec!["linux", "fedora"]);
    }
    #[test]
    fn ubuntu_section_keys_include_linux() {
        assert_eq!(TargetOs::Ubuntu.section_keys(), vec!["linux", "ubuntu"]);
    }

    #[test]
    fn darwin_package_manager_is_brew() {
        assert!(matches!(
            TargetOs::Darwin.package_manager_kind(),
            PackageManagerKind::Brew
        ));
    }

    #[test]
    fn fedora_package_manager_is_dnf() {
        assert!(matches!(
            TargetOs::Fedora.package_manager_kind(),
            PackageManagerKind::Dnf
        ));
    }

    #[test]
    fn ubuntu_package_manager_is_apt() {
        assert!(matches!(
            TargetOs::Ubuntu.package_manager_kind(),
            PackageManagerKind::Apt
        ));
    }

    #[test]
    fn unknown_os_package_manager_is_unknown() {
        assert!(matches!(
            TargetOs::Unknown("freebsd".into()).package_manager_kind(),
            PackageManagerKind::Unknown
        ));
    }
}
