use indexmap::IndexMap;
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct DecisionMatrix {
    #[serde(default)]
    pub schema_version: u32,
    #[serde(default)]
    pub title: Option<String>,
    pub criteria: IndexMap<String, Criterion>,
    pub alternatives: IndexMap<String, Alternative>,
    #[serde(skip)]
    pub category: Option<String>,
}

impl DecisionMatrix {
    pub fn with_category(mut self, category: impl Into<String>) -> Self {
        self.category = Some(category.into());
        self
    }

    pub fn category_label(&self) -> String {
        self.category
            .clone()
            .or_else(|| self.title.clone())
            .unwrap_or_else(|| "decision".to_owned())
    }

    pub fn normalized_weights(&self) -> IndexMap<String, f64> {
        let sum = self
            .criteria
            .values()
            .map(|criterion| criterion.weight)
            .sum::<f64>();
        if sum == 0.0 {
            return IndexMap::new();
        }
        self.criteria
            .iter()
            .map(|(name, criterion)| (name.clone(), criterion.weight / sum))
            .collect()
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct Criterion {
    pub weight: f64,
    pub direction: Direction,
    #[serde(default)]
    pub description: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Direction {
    Max,
    Min,
}

impl Direction {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Max => "max",
            Self::Min => "min",
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(transparent)]
pub struct Alternative {
    pub scores: IndexMap<String, f64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Ranking {
    pub ranked: Vec<Ranked>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Ranked {
    pub rank: usize,
    pub alternative: String,
    pub score: f64,
    pub distance_to_ideal: f64,
    pub distance_to_anti_ideal: f64,
}
