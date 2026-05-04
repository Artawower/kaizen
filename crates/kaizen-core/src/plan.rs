use indexmap::IndexMap;
use serde::{Deserialize, Serialize};

use crate::{TargetOs, UserSettings};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowPlan {
    pub target_os: String,
    pub selected_features: Vec<String>,
    pub install_plan: InstallPlan,
    pub config_plan: ConfigPlan,
    pub hook_plan: HookPlan,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstallPlan {
    pub programs: Vec<String>,
    pub mise_tools: IndexMap<String, String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct HookPlan {
    pub post_install: Vec<String>,
    pub post_apply: Vec<String>,
    pub post_update: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigPlan {
    pub backend: String,
    pub dotfiles_source: Option<String>,
    pub features_data: IndexMap<String, bool>,
    pub settings: UserSettings,
}

impl WorkflowPlan {
    pub fn new(
        target_os: TargetOs,
        selected_features: Vec<String>,
        install_plan: InstallPlan,
        config_plan: ConfigPlan,
        hook_plan: HookPlan,
        warnings: Vec<String>,
    ) -> Self {
        Self {
            target_os: target_os.to_string(),
            selected_features,
            install_plan,
            config_plan,
            hook_plan,
            warnings,
        }
    }
}
