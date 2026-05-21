use indexmap::IndexMap;

use crate::{ConfigPlan, HookPlan, InstallPlan, KaizenError, TargetOs, UserConfig, WorkflowPlan};

/// Stub: feature/variant/merge subsystems removed in steel-poc phase A.
/// Returns a minimal plan from config-level settings only.
pub fn build_plan_stub(
    config: &UserConfig,
    target_os: TargetOs,
) -> Result<WorkflowPlan, KaizenError> {
    let config_plan = ConfigPlan {
        backend: config.dotfiles.backend.clone().unwrap_or_default(),
        dotfiles_source: config.dotfiles.source.clone(),
        features_data: IndexMap::new(),
        settings: config.settings.clone(),
        extra: config.extra.clone(),
        variants: std::collections::BTreeMap::new(),
    };
    Ok(WorkflowPlan::new(
        target_os,
        vec![],
        InstallPlan {
            programs: vec![],
            dev_tools: IndexMap::new(),
            brew_source_formulas: vec![],
        },
        config_plan,
        HookPlan::default(),
        vec![],
    ))
}
