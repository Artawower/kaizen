use std::path::PathBuf;

#[derive(Debug, thiserror::Error)]
pub enum KaizenError {
    #[error("config not found at {path}")]
    ConfigNotFound { path: PathBuf },

    #[error("failed to parse config at {path}: {source}")]
    ConfigParse {
        path: PathBuf,
        #[source]
        source: toml::de::Error,
    },

    #[error("feature not found: {name}")]
    FeatureNotFound { name: String },

    #[error("invalid feature name '{name}': only [a-zA-Z0-9_-] allowed")]
    InvalidFeatureName { name: String },

    #[error("features directory not found: {path}")]
    FeaturesDirNotFound { path: PathBuf },

    #[error("failed to parse feature '{name}': {source}")]
    FeatureParse {
        name: String,
        #[source]
        source: toml::de::Error,
    },

    #[error("merge conflict: {0}")]
    MergeConflict(String),

    #[error("installer '{installer}' failed with exit code {code:?}")]
    InstallerFailed {
        installer: &'static str,
        code: Option<i32>,
    },

    #[error("{count} package(s) failed — see output above")]
    InstallerPartialFailure { count: usize, failed: Vec<String> },

    #[error("unsupported dotfiles backend '{backend}' — only 'chezmoi' is supported")]
    UnsupportedDotfilesBackend { backend: String },

    #[error("cannot determine chezmoi source directory — run 'chezmoi init' first")]
    ChezmoidataTargetUnknown,

    #[error("failed to serialize chezmoidata: {0}")]
    TomlSerialize(#[from] toml::ser::Error),

    #[error("hook command failed: `{command}` — {reason}")]
    HookFailed { command: String, reason: String },

    #[error("chezmoi init {url} failed with exit code {code:?}")]
    ChezmoidataInitFailed { url: String, code: Option<i32> },

    #[error("failed to parse manifest at {path}: {source}")]
    ManifestParse {
        path: PathBuf,
        #[source]
        source: toml::de::Error,
    },

    #[error("manifest schema {found} is newer than supported {supported} — upgrade kaizen")]
    ManifestSchemaTooNew { found: u32, supported: u32 },

    #[error("chezmoi apply failed with exit code {code:?}")]
    ChezmoidataApplyFailed { code: Option<i32> },

    #[error("command `{cmd}` failed with exit code {code:?}")]
    CommandFailed { cmd: String, code: Option<i32> },

    #[error("nix backend unavailable — neither home-manager nor darwin-rebuild found")]
    NixBackendUnavailable,

    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
}
