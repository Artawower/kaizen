use std::collections::HashSet;
use std::fmt;

use super::Config;
use validator::{Validate as _, ValidationErrors, ValidationErrorsKind};

/// Stable category for a configuration validation problem.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum ValidationCode {
    UnsupportedSchemaVersion,
    InvalidEmail,
    InvalidQuarantineDuration,
    InvalidFontSize,
    DuplicateWorkspaceName,
    InvalidAliasName,
    InvalidEnvironmentVariableName,
    InvalidModelProfileName,
    InvalidLangmapKey,
    EmptyValue,
}

impl ValidationCode {
    fn from_validator_error(path: &str, code: &str) -> Option<Self> {
        match (path, code) {
            ("schema-version", "range") => Some(Self::UnsupportedSchemaVersion),
            ("ui.typography.font_size", "range") => Some(Self::InvalidFontSize),
            (_, "regex") => Some(Self::InvalidQuarantineDuration),
            (_, "email") => Some(Self::InvalidEmail),
            (_, "length" | "empty_or_whitespace") => Some(Self::EmptyValue),
            _ => None,
        }
    }

    fn default_message(self) -> &'static str {
        match self {
            Self::UnsupportedSchemaVersion => "only schema version 1 is supported",
            Self::InvalidEmail => "expected a valid email address",
            Self::InvalidQuarantineDuration => {
                "expected a non-negative integer followed by w, d, m, or y"
            }
            Self::InvalidFontSize => "font size must be a finite number greater than zero",
            Self::DuplicateWorkspaceName => "workspace name is repeated",
            Self::InvalidAliasName => {
                "alias names must start with a lowercase ASCII letter and contain only lowercase ASCII letters, digits, underscores, or hyphens"
            }
            Self::InvalidEnvironmentVariableName => {
                "environment variable names must start with an ASCII letter or underscore and contain only ASCII letters, digits, or underscores"
            }
            Self::InvalidModelProfileName => {
                "model profile names must start with a lowercase ASCII letter and contain only lowercase ASCII letters, digits, underscores, or hyphens"
            }
            Self::InvalidLangmapKey => "keyboard langmap keys must contain exactly one character",
            Self::EmptyValue => "value must not be empty or whitespace-only",
        }
    }
}

/// A semantic validation problem, located by a TOML-style field path.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidationIssue {
    pub path: String,
    pub code: ValidationCode,
    pub message: String,
}

impl ValidationIssue {
    fn new(path: impl Into<String>, code: ValidationCode) -> Self {
        Self {
            path: path.into(),
            code,
            message: code.default_message().to_owned(),
        }
    }

    fn with_message(mut self, message: impl Into<String>) -> Self {
        self.message = message.into();
        self
    }
}

impl fmt::Display for ValidationIssue {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}: {}", self.path, self.message)
    }
}

impl std::error::Error for ValidationIssue {}

/// Validate the config using declarative field rules plus Kaizen-specific checks.
///
/// All issues are collected and returned in deterministic path order.
pub fn validate(config: &Config) -> Result<(), Vec<ValidationIssue>> {
    let mut issues = config
        .validate()
        .err()
        .map(|errors| append_validator_errors(&errors, ""))
        .unwrap_or_default();
    issues.extend(custom_issues(config));
    issues.sort_by(|left, right| left.path.cmp(&right.path).then(left.code.cmp(&right.code)));
    issues.dedup_by(|left, right| left.path == right.path && left.code == right.code);

    if issues.is_empty() {
        Ok(())
    } else {
        Err(issues)
    }
}

type ConfigValidator = fn(&Config) -> Vec<ValidationIssue>;

const CONFIG_VALIDATORS: &[ConfigValidator] = &[
    validate_font_size,
    validate_workspaces,
    validate_environment_names,
    validate_langmap_keys,
    validate_terminal_aliases,
    validate_ai_models,
];

fn custom_issues(config: &Config) -> Vec<ValidationIssue> {
    CONFIG_VALIDATORS
        .iter()
        .flat_map(|validator| validator(config))
        .collect()
}

fn append_validator_errors(errors: &ValidationErrors, prefix: &str) -> Vec<ValidationIssue> {
    let mut fields = errors.errors().iter().collect::<Vec<_>>();
    fields.sort_by_key(|(field, _)| field.to_string());

    fields
        .into_iter()
        .flat_map(|(field, kind)| {
            let path = join_path(prefix, config_field_to_toml_name(field));
            match kind {
                ValidationErrorsKind::Field(errors) => errors
                    .iter()
                    .filter_map(|error| {
                        ValidationCode::from_validator_error(&path, error.code.as_ref())
                            .map(|code| ValidationIssue::new(&path, code))
                    })
                    .collect(),
                ValidationErrorsKind::Struct(nested) => append_validator_errors(nested, &path),
                ValidationErrorsKind::List(nested) => nested
                    .iter()
                    .flat_map(|(index, errors)| {
                        append_validator_errors(errors, &format!("{path}[{index}]"))
                    })
                    .collect(),
            }
        })
        .collect()
}

/// Validator uses Rust field identifiers; public issue paths use serialized config names.
fn config_field_to_toml_name(name: &str) -> &str {
    match name {
        "schema_version" => "schema-version",
        "check_hash" => "check-hash",
        "allow_dependencies" => "allow-dependencies",
        "ai_validation" => "ai-validation",
        "allow_post_install" => "allow-post-install",
        "max_generations" => "max-generations",
        "use_fn_keys" => "use-fn-keys",
        other => other,
    }
}

fn join_path(prefix: &str, field: &str) -> String {
    if prefix.is_empty() {
        field.to_owned()
    } else {
        format!("{prefix}.{field}")
    }
}

fn validate_font_size(config: &Config) -> Vec<ValidationIssue> {
    let font_size = config
        .ui
        .as_ref()
        .and_then(|ui| ui.typography.as_ref())
        .and_then(|typography| typography.font_size);

    match font_size {
        Some(size) if !size.is_finite() => {
            vec![ValidationIssue::new(
                "ui.typography.font_size",
                ValidationCode::InvalidFontSize,
            )]
        }
        _ => Vec::new(),
    }
}

fn validate_workspaces(config: &Config) -> Vec<ValidationIssue> {
    let Some(workspaces) = config.ui.as_ref().and_then(|ui| ui.workspaces.as_ref()) else {
        return Vec::new();
    };

    let mut seen = HashSet::new();
    let mut issues = Vec::new();
    for (index, name) in workspaces.names.iter().enumerate() {
        if !seen.insert(name) {
            issues.push(
                ValidationIssue::new(
                    format!("ui.workspaces.names[{index}]"),
                    ValidationCode::DuplicateWorkspaceName,
                )
                .with_message(format!("workspace name {name:?} is repeated")),
            );
        }
    }
    issues
}

fn validate_environment_names(config: &Config) -> Vec<ValidationIssue> {
    config
        .env
        .iter()
        .flat_map(|env| env.keys())
        .filter(|name| !is_valid_environment_name(name))
        .map(|name| {
            ValidationIssue::new(
                format!("env.{name}"),
                ValidationCode::InvalidEnvironmentVariableName,
            )
        })
        .collect()
}

fn validate_langmap_keys(config: &Config) -> Vec<ValidationIssue> {
    config
        .keyboard
        .iter()
        .flat_map(|keyboard| keyboard.langmap.iter())
        .flat_map(|langmap| langmap.mappings.keys())
        .filter(|key| key.chars().count() != 1)
        .map(|key| {
            ValidationIssue::new(
                format!("keyboard.langmap.{key}"),
                ValidationCode::InvalidLangmapKey,
            )
        })
        .collect()
}

fn validate_terminal_aliases(config: &Config) -> Vec<ValidationIssue> {
    let mut issues = Vec::new();
    for (name, alias) in config
        .terminal
        .iter()
        .flat_map(|terminal| terminal.aliases.iter())
        .flat_map(|aliases| aliases.iter())
    {
        let path = format!("terminal.aliases.{name}");
        if !is_valid_profile_name(name) {
            issues.push(ValidationIssue::new(
                &path,
                ValidationCode::InvalidAliasName,
            ));
        }
        if let Err(errors) = alias.validate() {
            issues.extend(append_validator_errors(&errors, &path));
        }
    }
    issues
}

fn validate_ai_models(config: &Config) -> Vec<ValidationIssue> {
    let mut issues = Vec::new();
    for (name, value) in config
        .ai
        .iter()
        .flat_map(|ai| ai.models.iter())
        .flat_map(|models| models.iter())
    {
        let path = format!("ai.models.{name}");
        if !is_valid_profile_name(name) {
            issues.push(ValidationIssue::new(
                &path,
                ValidationCode::InvalidModelProfileName,
            ));
        }
        if value.trim().is_empty() {
            issues.push(ValidationIssue::new(&path, ValidationCode::EmptyValue));
        }
    }
    issues
}

fn is_valid_profile_name(name: &str) -> bool {
    let mut chars = name.chars();
    matches!(chars.next(), Some(first) if first.is_ascii_lowercase())
        && chars.all(|character| {
            character.is_ascii_lowercase()
                || character.is_ascii_digit()
                || character == '_'
                || character == '-'
        })
}

fn is_valid_environment_name(name: &str) -> bool {
    let mut chars = name.chars();
    matches!(chars.next(), Some(first) if first.is_ascii_alphabetic() || first == '_')
        && chars.all(|character| character.is_ascii_alphanumeric() || character == '_')
}

#[cfg(test)]
mod tests {
    use super::{ValidationCode, validate};
    use crate::config::{Config, Extends, SourceType};
    use std::collections::BTreeMap;

    fn valid_config() -> Config {
        let input = include_str!("../../../../docs/examples/config.example.toml");
        crate::config::parse(input).expect("example config parses")
    }

    fn has_issue(config: &Config, code: ValidationCode, path: &str) -> bool {
        validate(config)
            .expect_err("test config should fail validation")
            .iter()
            .any(|issue| issue.code == code && issue.path == path)
    }

    #[test]
    fn accepts_the_documented_config() {
        assert_eq!(validate(&valid_config()), Ok(()));
    }

    #[test]
    fn rejects_unsupported_schema_versions() {
        for version in [0, 2, u32::MAX] {
            let mut config = valid_config();
            config.schema_version = version;

            assert!(
                has_issue(
                    &config,
                    ValidationCode::UnsupportedSchemaVersion,
                    "schema-version"
                ),
                "version {version}"
            );
        }
    }

    #[test]
    fn rejects_invalid_email_addresses() {
        let mut config = valid_config();
        config.system.as_mut().unwrap().email = Some("not-an-email".into());

        assert!(has_issue(
            &config,
            ValidationCode::InvalidEmail,
            "system.email"
        ));
    }

    #[test]
    fn accepts_supported_quarantine_durations() {
        for duration in ["0d", "1w", "12m", "2y"] {
            let mut config = valid_config();
            config.privacy.as_mut().unwrap().quarantine = Some(duration.to_owned());
            assert_eq!(validate(&config), Ok(()), "duration {duration}");
        }
    }

    #[test]
    fn rejects_invalid_quarantine_durations() {
        for duration in ["", "w", "1", "-1d", "1q", "1ww", "1.5d", " 1d"] {
            let mut config = valid_config();
            config.privacy.as_mut().unwrap().quarantine = Some(duration.to_owned());
            assert!(
                has_issue(
                    &config,
                    ValidationCode::InvalidQuarantineDuration,
                    "privacy.quarantine"
                ),
                "duration {duration:?}"
            );
        }
    }

    #[test]
    fn accepts_only_finite_positive_font_sizes() {
        for font_size in [0.5, 1.0, 14.0, f64::MAX] {
            let mut config = valid_config();
            config
                .ui
                .as_mut()
                .unwrap()
                .typography
                .as_mut()
                .unwrap()
                .font_size = Some(font_size);
            assert_eq!(validate(&config), Ok(()), "font size {font_size}");
        }
    }

    #[test]
    fn rejects_non_positive_or_non_finite_font_sizes() {
        for font_size in [0.0, -1.0, f64::INFINITY, f64::NEG_INFINITY, f64::NAN] {
            let mut config = valid_config();
            config
                .ui
                .as_mut()
                .unwrap()
                .typography
                .as_mut()
                .unwrap()
                .font_size = Some(font_size);
            assert!(
                has_issue(
                    &config,
                    ValidationCode::InvalidFontSize,
                    "ui.typography.font_size"
                ),
                "font size {font_size}"
            );
        }
    }

    #[test]
    fn rejects_repeated_workspace_names_at_each_later_occurrence() {
        let mut config = valid_config();
        config
            .ui
            .as_mut()
            .unwrap()
            .workspaces
            .as_mut()
            .unwrap()
            .names = vec!["DEV".into(), "SOC".into(), "DEV".into(), "DEV".into()];

        let issues = validate(&config).expect_err("duplicate workspaces should fail");
        assert_eq!(
            issues
                .iter()
                .filter(|issue| issue.code == ValidationCode::DuplicateWorkspaceName)
                .map(|issue| issue.path.as_str())
                .collect::<Vec<_>>(),
            ["ui.workspaces.names[2]", "ui.workspaces.names[3]"]
        );
    }

    #[test]
    fn validates_terminal_alias_names() {
        let mut config = valid_config();
        {
            let aliases = config.terminal.as_mut().unwrap().aliases.as_mut().unwrap();
            aliases.insert("valid-name_2".into(), aliases["vcs"].clone());
        }
        assert_eq!(validate(&config), Ok(()));

        let aliases = config.terminal.as_mut().unwrap().aliases.as_mut().unwrap();
        aliases.insert("Bad Name".into(), aliases["vcs"].clone());
        assert!(has_issue(
            &config,
            ValidationCode::InvalidAliasName,
            "terminal.aliases.Bad Name"
        ));
    }

    #[test]
    fn validates_environment_variable_names() {
        let mut config = valid_config();
        config
            .env
            .as_mut()
            .unwrap()
            .insert("_VALID_2".into(), "value".into());
        assert_eq!(validate(&config), Ok(()));

        config
            .env
            .as_mut()
            .unwrap()
            .insert("2INVALID".into(), "value".into());
        assert!(has_issue(
            &config,
            ValidationCode::InvalidEnvironmentVariableName,
            "env.2INVALID"
        ));
    }

    #[test]
    fn validates_ai_model_profile_names_and_values() {
        let mut config = valid_config();
        {
            let models = config.ai.as_mut().unwrap().models.as_mut().unwrap();
            models.insert("valid_profile-2".into(), "provider/model".into());
        }
        assert_eq!(validate(&config), Ok(()));

        let models = config.ai.as_mut().unwrap().models.as_mut().unwrap();
        models.insert("Bad Profile".into(), "provider/model".into());
        models.insert("empty".into(), String::new());
        let issues = validate(&config).expect_err("invalid model config should fail");
        assert!(issues.iter().any(|issue| {
            issue.code == ValidationCode::InvalidModelProfileName
                && issue.path == "ai.models.Bad Profile"
        }));
        assert!(issues.iter().any(|issue| {
            issue.code == ValidationCode::EmptyValue && issue.path == "ai.models.empty"
        }));
    }

    #[test]
    fn validates_single_character_langmap_keys() {
        let mut config = valid_config();
        config
            .keyboard
            .as_mut()
            .unwrap()
            .langmap
            .as_mut()
            .unwrap()
            .mappings
            .insert("ж".into(), "w".into());
        assert_eq!(validate(&config), Ok(()));

        config
            .keyboard
            .as_mut()
            .unwrap()
            .langmap
            .as_mut()
            .unwrap()
            .mappings
            .insert("two".into(), "x".into());
        assert!(has_issue(
            &config,
            ValidationCode::InvalidLangmapKey,
            "keyboard.langmap.two"
        ));
    }

    #[test]
    fn rejects_blank_extends_paths_at_every_supported_level() {
        let mut config = valid_config();
        let blank = || Extends {
            path: "  ".into(),
            source_type: SourceType::Local,
        };
        config.extends = Some(blank());
        config.system.as_mut().unwrap().extends = Some(blank());
        config.privacy.as_mut().unwrap().extends = Some(blank());
        config.backup.as_mut().unwrap().extends = Some(blank());
        {
            let ui = config.ui.as_mut().unwrap();
            ui.extends = Some(blank());
            ui.theme.as_mut().unwrap().extends = Some(blank());
            ui.typography.as_mut().unwrap().extends = Some(blank());
            ui.workspaces.as_mut().unwrap().extends = Some(blank());
            ui.wallpaper.as_mut().unwrap().extends = Some(blank());
        }
        {
            let keyboard = config.keyboard.as_mut().unwrap();
            keyboard.extends = Some(blank());
            keyboard.langmap.as_mut().unwrap().extends = Some(blank());
        }
        {
            let terminal = config.terminal.as_mut().unwrap();
            terminal.extends = Some(blank());
            terminal
                .aliases
                .as_mut()
                .unwrap()
                .get_mut("vcs")
                .unwrap()
                .extends = Some(blank());
        }
        config.ai.as_mut().unwrap().extends = Some(blank());
        config.registry[0].extends = Some(blank());
        config.resources[0].extends = Some(blank());
        config.package.push(crate::config::PackageDeclaration {
            name: "pkg".into(),
            path: "./pkg".into(),
            source_type: SourceType::Local,
            enabled: None,
            arguments: None,
            extends: Some(blank()),
        });

        let issues = validate(&config).expect_err("blank extends paths should fail");
        let paths = issues
            .iter()
            .filter(|issue| issue.code == ValidationCode::EmptyValue)
            .map(|issue| issue.path.as_str())
            .collect::<Vec<_>>();
        assert_eq!(
            paths,
            [
                "ai.extends.path",
                "backup.extends.path",
                "extends.path",
                "keyboard.extends.path",
                "keyboard.langmap.extends.path",
                "package[0].extends.path",
                "privacy.extends.path",
                "registry[0].extends.path",
                "resources[0].extends.path",
                "system.extends.path",
                "terminal.aliases.vcs.extends.path",
                "terminal.extends.path",
                "ui.extends.path",
                "ui.theme.extends.path",
                "ui.typography.extends.path",
                "ui.wallpaper.extends.path",
                "ui.workspaces.extends.path",
            ]
        );
    }

    #[test]
    fn rejects_blank_registry_resource_package_and_alias_fields() {
        let mut config = valid_config();
        config.registry[0].name.clear();
        config.registry[0].source = " ".into();
        config.resources[0].path.clear();
        config.package.push(crate::config::PackageDeclaration {
            name: " ".into(),
            path: "".into(),
            source_type: SourceType::Local,
            enabled: None,
            arguments: None,
            extends: None,
        });
        config
            .terminal
            .as_mut()
            .unwrap()
            .aliases
            .as_mut()
            .unwrap()
            .insert(
                "vcs".into(),
                crate::config::TerminalAlias {
                    description: " ".into(),
                    extends: None,
                },
            );

        let issues = validate(&config).expect_err("blank required values should fail");
        for path in [
            "registry[0].name",
            "registry[0].source",
            "resources[0].path",
            "package[0].name",
            "package[0].path",
            "terminal.aliases.vcs.description",
        ] {
            assert!(
                issues.iter().any(|issue| {
                    issue.code == ValidationCode::EmptyValue && issue.path == path
                }),
                "missing issue for {path}: {issues:?}"
            );
        }
    }

    #[test]
    fn reports_all_invalid_values_in_one_pass() {
        let mut config = valid_config();
        config.schema_version = 0;
        config.privacy.as_mut().unwrap().quarantine = Some("bad".into());
        config
            .ui
            .as_mut()
            .unwrap()
            .typography
            .as_mut()
            .unwrap()
            .font_size = Some(0.0);

        let issues = validate(&config).expect_err("invalid values should be reported");
        assert_eq!(issues.len(), 3);
        assert_eq!(
            issues.iter().map(|issue| issue.code).collect::<Vec<_>>(),
            [
                ValidationCode::InvalidQuarantineDuration,
                ValidationCode::UnsupportedSchemaVersion,
                ValidationCode::InvalidFontSize,
            ]
        );
    }

    #[test]
    fn accepts_empty_optional_maps() {
        let mut config = valid_config();
        config.env = Some(BTreeMap::new());
        assert_eq!(validate(&config), Ok(()));
    }
}
