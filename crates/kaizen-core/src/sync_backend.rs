use crate::{KaizenError, WorkflowPlan};

// ── Options ──────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Default)]
pub struct SyncOpts {
    pub dry_run: bool,
}

#[derive(Debug, Clone, Default)]
pub struct UpdateOpts {
    pub dry_run: bool,
    /// `nix flake update` перед применением (только для NixSyncBackend)
    pub update_flake: bool,
}

#[derive(Debug, Clone, Default)]
pub struct CleanOpts {
    pub dry_run: bool,
}

// ── Reports ───────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Default)]
pub struct InstallReport {
    pub steps: Vec<String>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Default)]
pub struct ApplyReport {
    pub data_path: Option<std::path::PathBuf>,
}

#[derive(Debug, Clone, Default)]
pub struct SyncReport {
    pub install: InstallReport,
    pub apply: ApplyReport,
}

#[derive(Debug, Clone, Default)]
pub struct UpdateReport {
    pub upgraded: Vec<String>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Default)]
pub struct CleanReport {
    pub freed_bytes: Option<u64>,
    pub steps: Vec<String>,
}

// ── Preview ───────────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct SyncStep {
    pub label: String,
    pub command: String,
}

#[derive(Debug, Clone, Default)]
pub struct SyncPreview {
    pub steps: Vec<SyncStep>,
}

// ── Trait ─────────────────────────────────────────────────────────────────────

/// Абстракция полного lifecycle: install + apply + post-apply + update + clean.
///
/// CLI и Tauri работают через `detect_backend()` и никогда не знают
/// какая конкретная реализация используется.
pub trait SyncBackend: Send + Sync {
    fn id(&self) -> &'static str;
    fn is_available(&self) -> bool;

    /// Шаг 1: установить пакеты.
    ///
    /// - `UptSyncBackend`: `upt install <programs>`
    /// - `NixSyncBackend`: `darwin-rebuild switch` + `home-manager switch`
    ///   (игнорирует `plan.install_plan.programs` — Nix читает свои модули)
    ///
    /// Ошибка прерывает весь sync.
    fn install(&self, plan: &WorkflowPlan, opts: &SyncOpts) -> Result<InstallReport, KaizenError>;

    /// Шаг 2: применить dotfiles.
    ///
    /// Одинаково для всех бэкендов:
    /// записать `.chezmoidata.toml` → `chezmoi apply`
    ///
    /// Ошибка прерывает весь sync.
    fn apply(&self, plan: &WorkflowPlan, opts: &SyncOpts) -> Result<ApplyReport, KaizenError>;

    /// Шаг 3: post-apply.
    ///
    /// Одинаково для всех: `mise install && mise trust ~/.config/mise.toml`
    fn post_apply(&self, opts: &SyncOpts) -> Result<(), KaizenError>;

    /// Полный sync с правильным порядком шагов для каждого бэкенда.
    ///
    /// Default impl (upt): install → apply → post_apply  
    /// NixSyncBackend переопределяет: apply → install → post_apply
    /// (chezmoi apply первым, потому что Nix читает `.chezmoidata.toml`)
    fn sync(&self, plan: &WorkflowPlan, opts: &SyncOpts) -> Result<SyncReport, KaizenError> {
        let install = self.install(plan, opts)?;
        let apply = self.apply(plan, opts)?;
        self.post_apply(opts)?;
        Ok(SyncReport { install, apply })
    }

    /// Обновить пакеты. `opts.update_flake = true` дополнительно обновляет flake.lock.
    fn update(&self, plan: &WorkflowPlan, opts: &UpdateOpts) -> Result<UpdateReport, KaizenError>;

    /// Очистить кэши: nix GC, OS package cache, docker.
    fn clean(&self, opts: &CleanOpts) -> Result<CleanReport, KaizenError>;

    /// Превью без выполнения (dry-run, будущий `kaizen plan`).
    fn preview(&self, plan: &WorkflowPlan) -> SyncPreview;
}
