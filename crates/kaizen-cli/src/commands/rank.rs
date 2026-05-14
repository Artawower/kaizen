use std::path::PathBuf;

use anyhow::{anyhow, Result};
use kaizen_core::rank::format::md::{render_md, render_md_section};
use kaizen_core::rank::format::table::render_table;
use kaizen_core::rank::{load_decisions_dir, rank};
use kaizen_core::{FileSystem, PathProvider};

pub fn run(
    category: Option<String>,
    md: bool,
    all: bool,
    dir: Option<PathBuf>,
    paths: &dyn PathProvider,
    fs: &dyn FileSystem,
) -> Result<()> {
    print!("{}", render(category.as_deref(), md, all, dir, paths, fs)?);
    Ok(())
}

pub fn render(
    category: Option<&str>,
    md: bool,
    all: bool,
    dir: Option<PathBuf>,
    paths: &dyn PathProvider,
    fs: &dyn FileSystem,
) -> Result<String> {
    let decisions_dir = decisions_dir(dir, paths)?;
    let decisions = load_decisions_dir(&decisions_dir, fs)?;

    if all {
        return render_all(md, decisions);
    }

    let Some(category) = category else {
        return Ok(render_category_list(&decisions));
    };

    let (_, matrix) = decisions
        .iter()
        .find(|(name, _)| name == category)
        .ok_or_else(|| anyhow!("unknown rank category '{category}'"))?;
    let ranking = rank(matrix)?;
    let title = title(category, matrix.title.as_deref());

    if md {
        return Ok(render_md(&title, matrix, &ranking));
    }
    Ok(render_table(&title, matrix, &ranking))
}

fn decisions_dir(dir: Option<PathBuf>, paths: &dyn PathProvider) -> Result<PathBuf> {
    if let Some(dir) = dir {
        return Ok(dir);
    }
    paths
        .config_dir()
        .map(|dir| dir.join("kaizen").join("decisions"))
        .ok_or_else(|| anyhow!("cannot determine config directory"))
}

fn render_category_list(decisions: &[(String, kaizen_core::DecisionMatrix)]) -> String {
    if decisions.is_empty() {
        return "No rank decisions found.\n".to_owned();
    }
    decisions
        .iter()
        .map(|(name, matrix)| format!("{:<16} {}", name, matrix.title.as_deref().unwrap_or("")))
        .collect::<Vec<_>>()
        .join("\n")
        + "\n"
}

fn render_all(md: bool, decisions: Vec<(String, kaizen_core::DecisionMatrix)>) -> Result<String> {
    if md {
        let mut out = String::from("# Kaizen rankings\n\n");
        for (idx, (category, matrix)) in decisions.iter().enumerate() {
            let ranking = rank(matrix)?;
            if idx > 0 {
                out.push('\n');
            }
            out.push_str(&render_md_section(
                &title(category, matrix.title.as_deref()),
                matrix,
                &ranking,
            ));
        }
        return Ok(out);
    }

    let mut rendered = Vec::new();
    for (category, matrix) in &decisions {
        let ranking = rank(matrix)?;
        rendered.push(render_table(
            &title(category, matrix.title.as_deref()),
            matrix,
            &ranking,
        ));
    }
    Ok(rendered.join("\n"))
}

fn title(category: &str, title: Option<&str>) -> String {
    title.unwrap_or(category).to_owned()
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;
    use crate::filesystem::StdFileSystem;

    struct FixedPaths {
        config: PathBuf,
    }

    impl PathProvider for FixedPaths {
        fn home_dir(&self) -> Option<PathBuf> {
            None
        }

        fn config_dir(&self) -> Option<PathBuf> {
            Some(self.config.clone())
        }

        fn is_tool_available(&self, _: &str) -> bool {
            false
        }
    }

    const TERMINAL: &str = r#"
schema_version = 1
title = "Terminal emulator"

[criteria]
speed = { weight = 1, direction = "max" }

[alternatives.ghostty]
speed = 10

[alternatives.wezterm]
speed = 8
"#;

    #[test]
    fn rank_command_lists_categories_when_no_arg() {
        let tmp = tempfile::tempdir().unwrap();
        let decisions = tmp.path().join("kaizen/decisions");
        std::fs::create_dir_all(&decisions).unwrap();
        std::fs::write(decisions.join("terminal.toml"), TERMINAL).unwrap();
        let paths = FixedPaths {
            config: tmp.path().to_owned(),
        };

        let output = render(None, false, false, None, &paths, &StdFileSystem).unwrap();

        assert!(output.contains("terminal"));
        assert!(output.contains("Terminal emulator"));
    }

    #[test]
    fn rank_command_unknown_category_errors() {
        let tmp = tempfile::tempdir().unwrap();
        let decisions = tmp.path().join("kaizen/decisions");
        std::fs::create_dir_all(&decisions).unwrap();
        std::fs::write(decisions.join("terminal.toml"), TERMINAL).unwrap();
        let paths = FixedPaths {
            config: tmp.path().to_owned(),
        };

        let error = render(Some("missing"), false, false, None, &paths, &StdFileSystem)
            .unwrap_err()
            .to_string();

        assert!(error.contains("unknown rank category 'missing'"));
    }
}
