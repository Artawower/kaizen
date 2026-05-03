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
        if cfg!(target_os = "macos") {
            return TargetOs::Darwin;
        }

        #[cfg(target_os = "linux")]
        {
            let content = std::fs::read_to_string("/etc/os-release").unwrap_or_default();
            return Self::from_os_release(&content);
        }

        #[allow(unreachable_code)]
        TargetOs::Unknown(std::env::consts::OS.to_string())
    }

    pub fn from_os_release(content: &str) -> Self {
        let id = os_release_field(content, "ID");
        let id_like: Vec<&str> = os_release_field(content, "ID_LIKE")
            .split_whitespace()
            .collect();

        if id == "fedora" || id_like.contains(&"fedora") {
            return TargetOs::Fedora;
        }
        if id == "ubuntu" || id_like.contains(&"ubuntu") {
            return TargetOs::Ubuntu;
        }
        TargetOs::Linux
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

    pub fn is_linux(&self) -> bool {
        matches!(self, TargetOs::Fedora | TargetOs::Ubuntu | TargetOs::Linux)
    }
}

fn os_release_field<'a>(content: &'a str, key: &str) -> &'a str {
    let prefix = format!("{key}=");
    content
        .lines()
        .find(|l| l.starts_with(&prefix))
        .map(|l| l[prefix.len()..].trim_matches('"'))
        .unwrap_or("")
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
    fn detects_fedora_by_id() {
        let os = TargetOs::from_os_release("ID=fedora\n");
        assert_eq!(os, TargetOs::Fedora);
    }

    #[test]
    fn detects_fedora_by_id_like() {
        let os = TargetOs::from_os_release("ID=nobara\nID_LIKE=fedora\n");
        assert_eq!(os, TargetOs::Fedora);
    }

    #[test]
    fn detects_ubuntu_by_id() {
        let os = TargetOs::from_os_release("ID=ubuntu\n");
        assert_eq!(os, TargetOs::Ubuntu);
    }

    #[test]
    fn detects_ubuntu_by_id_like() {
        let os = TargetOs::from_os_release("ID=pop\nID_LIKE=\"ubuntu debian\"\n");
        assert_eq!(os, TargetOs::Ubuntu);
    }

    #[test]
    fn falls_back_to_generic_linux() {
        let os = TargetOs::from_os_release("ID=arch\n");
        assert_eq!(os, TargetOs::Linux);
    }

    #[test]
    fn fedora_section_keys_include_linux() {
        assert_eq!(TargetOs::Fedora.section_keys(), vec!["linux", "fedora"]);
    }
}
