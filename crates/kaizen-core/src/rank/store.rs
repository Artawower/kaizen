use std::path::Path;

use crate::rank::DecisionMatrix;
use crate::{FileSystem, KaizenError};

pub fn load_decisions_dir(
    path: &Path,
    fs: &dyn FileSystem,
) -> Result<Vec<(String, DecisionMatrix)>, KaizenError> {
    if !fs.is_dir(path) {
        return Ok(vec![]);
    }

    let mut files = fs
        .read_dir_paths(path)?
        .into_iter()
        .filter(|entry| entry.extension().is_some_and(|ext| ext == "toml"))
        .collect::<Vec<_>>();
    files.sort();

    files
        .into_iter()
        .map(|file| {
            let category = file
                .file_stem()
                .and_then(|stem| stem.to_str())
                .unwrap_or("decision")
                .to_owned();
            let content = fs.read_to_string(&file)?;
            let matrix = toml::from_str::<DecisionMatrix>(&content)
                .map_err(|source| KaizenError::RankParse {
                    category: category.clone(),
                    source,
                })?
                .with_category(category.clone());
            Ok((category, matrix))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::*;
    use crate::fs::mem::MemFileSystem;

    const TERMINAL: &str = r#"
schema_version = 1
title = "Terminal emulator"

[criteria]
startup_time = { weight = 0.30, direction = "max", description = "Boot speed (1-10)" }
ligatures    = { weight = 0.15, direction = "max" }
ram_usage    = { weight = 0.20, direction = "min" }
gpu_accel    = { weight = 0.20, direction = "max" }
custom       = { weight = 0.15, direction = "max" }

[alternatives.ghostty]
startup_time = 9.5
ligatures    = 10
ram_usage    = 4
gpu_accel    = 10
custom       = 9

[alternatives.wezterm]
startup_time = 7
ligatures    = 10
ram_usage    = 7
gpu_accel    = 10
custom       = 10
"#;

    #[test]
    fn loads_decision_from_toml() {
        let fs = MemFileSystem::new();
        fs.write(Path::new("/decisions/terminal.toml"), TERMINAL.as_bytes())
            .unwrap();

        let decisions = load_decisions_dir(Path::new("/decisions"), &fs).unwrap();

        assert_eq!(decisions.len(), 1);
        assert_eq!(decisions[0].0, "terminal");
        assert_eq!(decisions[0].1.title.as_deref(), Some("Terminal emulator"));
        assert_eq!(decisions[0].1.alternatives.len(), 2);
    }

    #[test]
    fn loads_multiple_decisions_from_dir() {
        let fs = MemFileSystem::new();
        fs.write(Path::new("/decisions/terminal.toml"), TERMINAL.as_bytes())
            .unwrap();
        fs.write(Path::new("/decisions/vcs.toml"), TERMINAL.as_bytes())
            .unwrap();

        let decisions = load_decisions_dir(Path::new("/decisions"), &fs).unwrap();

        assert_eq!(
            decisions
                .iter()
                .map(|(category, _)| category.as_str())
                .collect::<Vec<_>>(),
            vec!["terminal", "vcs"]
        );
    }

    #[test]
    fn skip_non_toml_files() {
        let fs = MemFileSystem::new();
        fs.write(Path::new("/decisions/terminal.toml"), TERMINAL.as_bytes())
            .unwrap();
        fs.write(Path::new("/decisions/readme.md"), b"ignore")
            .unwrap();

        let decisions = load_decisions_dir(Path::new("/decisions"), &fs).unwrap();

        assert_eq!(decisions.len(), 1);
        assert_eq!(decisions[0].0, "terminal");
    }
}
