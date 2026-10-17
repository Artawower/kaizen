//! User configuration models, TOML parsing, and validation.
//!
//! This module does not perform filesystem or network access. Loading and
//! resolving `extends` references are separate application-layer steps.

use std::collections::BTreeMap;
use std::sync::LazyLock;

use regex::Regex;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use validator::Validate;

mod validation;
pub use validation::{ValidationCode, ValidationIssue, validate};

static QUARANTINE_REGEX: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[0-9]+[wdmy]$").expect("valid quarantine regex"));

fn validate_not_blank(value: &str) -> Result<(), validator::ValidationError> {
    if value.trim().is_empty() {
        Err(validator::ValidationError::new("empty_or_whitespace"))
    } else {
        Ok(())
    }
}

fn positive_optional_f64_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
    let mut number = f64::json_schema(generator);
    number.insert("exclusiveMinimum".into(), 0.0.into());
    schemars::json_schema!({ "anyOf": [number, { "type": "null" }] })
}

/// Parse a Kaizen user configuration from TOML.
pub fn parse(input: &str) -> Result<Config, toml::de::Error> {
    toml::from_str(input)
}

/// Root user configuration (`config.toml`).
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
#[serde(deny_unknown_fields)]
pub struct Config {
    /// Kaizen config schema version. The v1 engine accepts only `1`.
    #[serde(rename = "schema-version")]
    #[validate(range(min = 1, max = 1))]
    pub schema_version: u32,
    /// Optional base configuration to merge before this config.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub extends: Option<Extends>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub system: Option<SystemConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub privacy: Option<PrivacyConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub backup: Option<BackupConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub ui: Option<UiConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub keyboard: Option<KeyboardConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub env: Option<BTreeMap<String, String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub terminal: Option<TerminalConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub ai: Option<AiConfig>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    #[validate(nested)]
    pub registry: Vec<RegistrySource>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    #[validate(nested)]
    pub resources: Vec<Resource>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    #[validate(nested)]
    pub package: Vec<PackageDeclaration>,
}

/// Reference to an inherited local, Git, or URL configuration.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
#[serde(deny_unknown_fields)]
pub struct Extends {
    #[validate(length(min = 1), custom(function = "validate_not_blank"))]
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

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
#[serde(deny_unknown_fields)]
pub struct SystemConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(email)]
    pub email: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub full_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
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
    #[validate(regex(path = *QUARANTINE_REGEX))]
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
    #[validate(nested)]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
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
    #[validate(nested)]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
#[serde(deny_unknown_fields)]
pub struct UiConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub theme: Option<ThemeConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub typography: Option<TypographyConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub workspaces: Option<WorkspacesConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub wallpaper: Option<WallpaperConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
#[serde(deny_unknown_fields)]
pub struct ThemeConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub light: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dark: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
#[serde(deny_unknown_fields)]
pub struct TypographyConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub font_family: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(range(exclusive_min = 0.0))]
    #[schemars(schema_with = "positive_optional_f64_schema")]
    pub font_size: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
#[serde(deny_unknown_fields)]
pub struct WorkspacesConfig {
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub names: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
#[serde(deny_unknown_fields)]
pub struct WallpaperConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub directory: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub directory_light: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub directory_dark: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
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
    #[validate(nested)]
    pub langmap: Option<LangmapConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
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
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
pub struct LangmapConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub extends: Option<Extends>,
    #[serde(flatten)]
    pub mappings: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
#[serde(deny_unknown_fields)]
pub struct TerminalConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub aliases: Option<BTreeMap<String, TerminalAlias>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
#[serde(deny_unknown_fields)]
pub struct TerminalAlias {
    #[validate(length(min = 1), custom(function = "validate_not_blank"))]
    pub description: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
#[serde(deny_unknown_fields)]
pub struct AiConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub models: Option<BTreeMap<String, String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
#[serde(deny_unknown_fields)]
pub struct RegistrySource {
    #[validate(length(min = 1), custom(function = "validate_not_blank"))]
    pub name: String,
    #[validate(length(min = 1), custom(function = "validate_not_blank"))]
    pub source: String,
    #[serde(rename = "type")]
    pub source_type: SourceType,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enabled: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
#[serde(deny_unknown_fields)]
pub struct Resource {
    #[validate(length(min = 1), custom(function = "validate_not_blank"))]
    pub path: String,
    #[serde(rename = "type")]
    pub source_type: SourceType,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
    pub extends: Option<Extends>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, validator::Validate)]
#[serde(deny_unknown_fields)]
pub struct PackageDeclaration {
    #[validate(length(min = 1), custom(function = "validate_not_blank"))]
    pub name: String,
    #[validate(length(min = 1), custom(function = "validate_not_blank"))]
    pub path: String,
    #[serde(rename = "type")]
    pub source_type: SourceType,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enabled: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub arguments: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[validate(nested)]
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

    #[test]
    fn font_size_schema_boundary_matches_runtime_validation()
    -> Result<(), Box<dyn std::error::Error>> {
        let mut config = super::parse(include_str!("../../../docs/examples/config.example.toml"))?;
        let typography = config
            .ui
            .as_mut()
            .and_then(|ui| ui.typography.as_mut())
            .ok_or_else(|| std::io::Error::other("example config should declare typography"))?;
        typography.font_size = Some(0.0);

        assert!(
            super::validate(&config).is_err(),
            "zero font size is invalid"
        );

        let generated = schemars::schema_for!(super::Config);
        let generated = serde_json::to_value(generated)?;
        let font_size = &generated["$defs"]["TypographyConfig"]["properties"]["font_size"];
        assert_eq!(font_size["anyOf"][0]["exclusiveMinimum"], 0.0);
        assert!(font_size["anyOf"][0].get("minimum").is_none());
        Ok(())
    }
}
