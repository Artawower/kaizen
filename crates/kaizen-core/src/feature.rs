use indexmap::IndexMap;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct FeatureFile {
    #[serde(default)]
    pub meta: MetaSection,

    #[serde(default)]
    pub programs: Option<ProgramSection>,

    #[serde(default)]
    pub mise: Option<MiseConfig>,

    #[serde(default)]
    pub atoms: IndexMap<String, AtomSection>,

    #[serde(default)]
    pub os: IndexMap<String, OsSection>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct MetaSection {
    pub description: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct ProgramSection {
    #[serde(default)]
    pub packages: Vec<String>,

    #[serde(default)]
    pub overrides: IndexMap<String, IndexMap<String, String>>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct MiseConfig {
    #[serde(default)]
    pub tools: IndexMap<String, String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct AtomSection {
    #[serde(default)]
    pub programs: Option<ProgramSection>,

    #[serde(default)]
    pub mise: Option<MiseConfig>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct OsSection {
    #[serde(default)]
    pub programs: Option<ProgramSection>,

    #[serde(default)]
    pub mise: Option<MiseConfig>,
}
