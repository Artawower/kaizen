//! User configuration models, TOML parsing, and generated JSON Schema.
//!
//! This module is a pure format boundary: callers provide the TOML text, and no
//! filesystem or network access is performed here. Semantic validation and
//! `extends` loading/resolution are separate steps.

use std::collections::BTreeMap;

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// Parse a Kaizen user configuration from TOML.
pub fn parse(input: &str) -> Result<Config, toml::de::Error> {
    toml::from_str(input)
}

/// Root user configuration (`config.toml`).
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Config {
    /// Kaizen config schema version. The v1 engine accepts only `1`.
    #[serde(rename = "schema-version")]
    #[schemars(range(min = 1, max = 1))]
    pub schema_version: u32,
    /// Optional base configuration to merge before this config.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub system: Option<SystemConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub privacy: Option<PrivacyConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub backup: Option<BackupConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ui: Option<UiConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub keyboard: Option<KeyboardConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub env: Option<BTreeMap<String, String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub terminal: Option<TerminalConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ai: Option<AiConfig>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub registry: Vec<RegistrySource>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub resources: Vec<Resource>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub package: Vec<PackageDeclaration>,
}

/// Reference to an inherited local, Git, or URL configuration.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Extends {
    pub path: String,
    #[serde(rename = "type")]
    pub source_type: SourceType,
}

/// Source kind for registries, resources, and package declarations.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum SourceType {
    Local,
    Git,
    Url,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SystemConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[schemars(email)]
    pub email: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub full_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct PrivacyConfig {
    #[serde(
        rename = "check-hash",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub check_hash: Option<bool>,
    #[serde(
        rename = "allow-dependencies",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub allow_dependencies: Option<bool>,
    #[serde(
        rename = "ai-validation",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub ai_validation: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[schemars(regex(pattern = r"^[0-9]+[wdmy]$"))]
    pub quarantine: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub foss: Option<bool>,
    #[serde(
        rename = "allow-post-install",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub allow_post_install: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct BackupConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enabled: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub directory: Option<String>,
    #[serde(
        rename = "max-generations",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub max_generations: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct UiConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub theme: Option<ThemeConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub typography: Option<TypographyConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workspaces: Option<WorkspacesConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wallpaper: Option<WallpaperConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ThemeConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub light: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dark: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct TypographyConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub font_family: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub font_size: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WorkspacesConfig {
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub names: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WallpaperConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub directory: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub directory_light: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub directory_dark: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct KeyboardConfig {
    #[serde(
        rename = "use-fn-keys",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub use_fn_keys: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub layout: Option<KeyboardLayout>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub langmap: Option<LangmapConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum KeyboardLayout {
    Qwerty,
    Dvorak,
    Colemak,
    ColemakDh,
}

/// Keyboard mapping keys are intentionally dynamic single-character strings.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct LangmapConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
    #[serde(flatten)]
    pub mappings: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct TerminalConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub aliases: Option<BTreeMap<String, TerminalAlias>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct TerminalAlias {
    pub description: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AiConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub models: Option<BTreeMap<String, String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct RegistrySource {
    pub name: String,
    pub source: String,
    #[serde(rename = "type")]
    pub source_type: SourceType,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enabled: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Resource {
    pub path: String,
    #[serde(rename = "type")]
    pub source_type: SourceType,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct PackageDeclaration {
    pub name: String,
    pub path: String,
    #[serde(rename = "type")]
    pub source_type: SourceType,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enabled: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub arguments: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extends: Option<Extends>,
}

#[cfg(test)]
mod tests {
    use super::parse;

    #[test]
    fn parses_config_example() {
        let input = include_str!("../../../docs/examples/config.example.toml");
        let config = parse(input).expect("config example should match the Rust config model");

        assert_eq!(config.schema_version, 1);
        assert_eq!(config.terminal.unwrap().aliases.unwrap().len(), 6);
        assert_eq!(config.registry.len(), 1);
        assert_eq!(config.resources.len(), 1);
    }

    #[test]
    fn checked_in_json_schema_matches_rust_types() {
        let generated = schemars::schema_for!(super::Config);
        let generated =
            serde_json::to_string_pretty(&generated).expect("serialize generated schema");
        let checked_in = include_str!("../../../docs/schemas/config.schema.json").trim();

        assert_eq!(generated, checked_in);
    }
}
