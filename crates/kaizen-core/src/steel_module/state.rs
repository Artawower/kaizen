use std::collections::HashMap;

use steel::rvals::SteelVal;

// ── Phase ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Default)]
pub enum Phase {
    #[default]
    Collection,
    Apply,
}

// ── Declarations ──────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct ModuleDecl {
    pub name: String,
    pub os: Vec<String>,
    pub group: Option<String>,
    pub stability: String,
    pub description: String,
}

#[derive(Debug, Clone)]
pub enum PackageManager {
    Nix,
    Brew,
    Mise,
}

#[derive(Debug, Clone)]
pub struct PackageDecl {
    pub manager: PackageManager,
    pub name: String,
}

#[derive(Debug, Clone)]
pub struct ActionDecl {
    pub id: String,
    pub description: String,
    pub mnemonic: Option<Vec<String>>,
}

#[derive(Debug, Clone)]
pub struct BindingDecl {
    pub module_name: String,
    pub action: String,
    pub key: String,
    pub mode: String,
}

// ── Aggregate state ───────────────────────────────────────────────────────────

/// All declarations collected during the Steel evaluation phases.
///
/// Stored in a thread-local `RefCell` so `SteelVal` (which is `!Send`) never
/// crosses thread boundaries.
#[derive(Default)]
pub struct KaizenState {
    pub modules: Vec<ModuleDecl>,
    pub packages: Vec<PackageDecl>,
    pub actions: HashMap<String, ActionDecl>,
    /// Default bindings from feature modules.
    pub bindings: Vec<BindingDecl>,
    /// Binding overrides from user/*.scm (applied after defaults).
    pub overrides: Vec<BindingDecl>,
    /// Context passed to `SteelEngine::new` — visible in runtime.json but shadowed by globals.
    pub initial_context: HashMap<String, String>,
    /// Global key-value store written by `set-global!`, readable via `get-context`.
    pub globals: HashMap<String, String>,
    /// Per-module config written by `set-module-config!`.
    pub module_configs: HashMap<String, HashMap<String, String>>,
    /// Provider functions registered via `provide-hook`.
    pub hook_providers: HashMap<String, SteelVal>,
    /// Consumer functions registered via `use-hook`.
    pub hook_consumers: Vec<(String, SteelVal)>,
    /// Callbacks registered via `on-apply!`.
    pub apply_callbacks: Vec<SteelVal>,
    /// Callbacks registered via `on-re-add!`.
    pub re_add_callbacks: Vec<SteelVal>,
    /// Callbacks registered via `on-bump!`.
    pub bump_callbacks: Vec<SteelVal>,
    /// Callbacks registered via `on-update!`.
    pub update_callbacks: Vec<SteelVal>,
    pub phase: Phase,
    /// Name of the module currently being loaded.
    pub current_module: String,
    /// Directory of the module currently being loaded (for `read-file` resolution).
    pub current_module_dir: Option<std::path::PathBuf>,
    /// Persistent map of module name → source directory.
    pub module_dirs: std::collections::HashMap<String, std::path::PathBuf>,
}

impl KaizenState {
    /// Return effective bindings: defaults with user overrides applied on top.
    ///
    /// An override matches when `module_name` **and** `action` are equal;
    /// unmatched overrides are appended.
    pub fn effective_bindings(&self) -> Vec<BindingDecl> {
        let mut result = self.bindings.clone();
        for ov in &self.overrides {
            if let Some(existing) = result
                .iter_mut()
                .find(|b| b.module_name == ov.module_name && b.action == ov.action)
            {
                *existing = ov.clone();
            } else {
                result.push(ov.clone());
            }
        }
        result
    }

    /// Serialize collected state to a JSON value for tooling consumption.
    pub fn to_runtime_json(&self) -> serde_json::Value {
        let actions: serde_json::Map<String, serde_json::Value> = self
            .actions
            .iter()
            .map(|(id, a)| {
                (
                    id.clone(),
                    serde_json::json!({
                        "description": a.description,
                        "mnemonic": a.mnemonic,
                    }),
                )
            })
            .collect();

        let effective = self.effective_bindings();
        let modules: serde_json::Map<String, serde_json::Value> = self
            .modules
            .iter()
            .map(|m| {
                let bindings: serde_json::Map<String, serde_json::Value> = effective
                    .iter()
                    .filter(|b| b.module_name == m.name)
                    .map(|b| (b.action.clone(), serde_json::json!(b.key)))
                    .collect();
                (
                    m.name.clone(),
                    serde_json::json!({
                        "active": true,
                        "group": m.group,
                        "bindings": bindings,
                    }),
                )
            })
            .collect();

        // Merge: initial_context as base, globals shadow it.
        let mut context = self.initial_context.clone();
        context.extend(self.globals.clone());

        serde_json::json!({
            "context": context,
            "actions": actions,
            "modules": modules,
        })
    }
}
