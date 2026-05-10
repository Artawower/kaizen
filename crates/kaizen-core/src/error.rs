use std::path::PathBuf;

fn chezmoi_apply_message(code: &Option<i32>, reason: &Option<String>) -> String {
    match reason.as_deref() {
        Some(r)
            if r.contains("could not open a new TTY")
                || r.contains("has changed since chezmoi") =>
        {
            format!(
                "chezmoi apply failed: managed files have local changes\n\n\
                 Run `kaizen sync --force` (or `kaizen install --force`) to overwrite.\n\n\
                 Details: {r}"
            )
        }
        Some(r) if r.contains("map has no entry for key") => {
            format!(
                "chezmoi apply failed\n\n{r}\n\n\
                 Hint: a template references a missing feature key.\n\
                 Run 'kaizen configure' or check ~/.config/kaizen/data.toml."
            )
        }
        Some(r) => format!("chezmoi apply failed\n\n{r}"),
        None => format!("chezmoi apply failed with exit code {code:?}"),
    }
}

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

    #[error("failed to serialize kaizen data: {0}")]
    TomlSerialize(#[from] toml::ser::Error),

    #[error("hook command failed: `{command}` — {reason}")]
    HookFailed { command: String, reason: String },

    #[error("chezmoi init {url} failed with exit code {code:?}")]
    ChezmoidataInitFailed { url: String, code: Option<i32> },

    #[error("git pull failed for {path} — check network or repository access")]
    GitPullFailed { path: PathBuf },

    #[error("failed to parse manifest at {path}: {source}")]
    ManifestParse {
        path: PathBuf,
        #[source]
        source: toml::de::Error,
    },

    #[error("manifest schema {found} is newer than supported {supported} — upgrade kaizen")]
    ManifestSchemaTooNew { found: u32, supported: u32 },

    #[error("{}", chezmoi_apply_message(.code, .reason))]
    ChezmoidataApplyFailed {
        code: Option<i32>,
        reason: Option<String>,
    },

    #[error("command `{cmd}` failed with exit code {code:?}")]
    CommandFailed { cmd: String, code: Option<i32> },

    #[error("cannot determine home directory — $HOME is not set")]
    HomeDirUnavailable,

    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
}
