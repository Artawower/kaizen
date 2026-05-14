use std::path::PathBuf;

use anyhow::{anyhow, Result};
use kaizen_core::rank::format::md::{render_md, render_md_section};
use kaizen_core::rank::{load_decisions_dir, rank};
use kaizen_core::{DecisionMatrix, FileSystem, PathProvider, Ranking};
use owo_colors::OwoColorize;

use crate::output;

pub fn run(
    category: Option<String>,
    md: bool,
    all: bool,
    dir: Option<PathBuf>,
    paths: &dyn PathProvider,
    fs: &dyn FileSystem,
) -> Result<()> {
    if md || (!all && category.is_none()) {
        print!("{}", render(category.as_deref(), md, all, dir, paths, fs)?);
        return Ok(());
    }

    print_styled(category.as_deref(), all, dir, paths, fs)
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
        if md {
            return render_all_md(decisions);
        }
        return Err(anyhow!("styled table output must be printed directly"));
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
    Err(anyhow!("styled table output must be printed directly"))
}

pub fn print_styled(
    category: Option<&str>,
    all: bool,
    dir: Option<PathBuf>,
    paths: &dyn PathProvider,
    fs: &dyn FileSystem,
) -> Result<()> {
    let decisions_dir = decisions_dir(dir, paths)?;
    let decisions = load_decisions_dir(&decisions_dir, fs)?;

    if all {
        output::page_header("rank: all");
        for (idx, (category, matrix)) in decisions.iter().enumerate() {
            if idx > 0 {
                println!();
            }
            let ranking = rank(matrix)?;
            output::header(&title(category, matrix.title.as_deref()));
            print_rank_table(matrix, &ranking);
        }
        return Ok(());
    }

    let Some(category) = category else {
        print!("{}", render_category_list(&decisions));
        return Ok(());
    };
    let (_, matrix) = decisions
        .iter()
        .find(|(name, _)| name == category)
        .ok_or_else(|| anyhow!("unknown rank category '{category}'"))?;
    let ranking = rank(matrix)?;

    output::page_header(&format!("rank: {category}"));
    print_rank_table(matrix, &ranking);
    Ok(())
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

fn render_category_list(decisions: &[(String, DecisionMatrix)]) -> String {
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

fn render_all_md(decisions: Vec<(String, DecisionMatrix)>) -> Result<String> {
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
    Ok(out)
}

fn print_rank_table(matrix: &DecisionMatrix, ranking: &Ranking) {
    let (alternative_width, score_width) = column_widths(ranking);
    let top_score = ranking.ranked.first().map(|item| item.score).unwrap_or(0.0);

    println!(
        "  {}  {:<alternative_width$}  {:>score_width$}    {}",
        "#".dimmed().bold(),
        "alternative".dimmed().bold(),
        "score".dimmed().bold(),
        "gap".dimmed().bold(),
    );

    for item in &ranking.ranked {
        let gap = if item.rank == 1 {
            "—".to_owned()
        } else {
            format!("{:.3}", item.score - top_score).replace('-', "−")
        };
        let marker = if item.rank == 1 {
            "●".green().to_string()
        } else {
            " ".to_owned()
        };
        let rank = format!("{:>2}", item.rank);
        let alternative = format!("{:<alternative_width$}", item.alternative);
        let score = format!("{:>score_width$.3}", item.score);
        if item.rank == 1 {
            println!(
                "{} {}  {}  {}    {}",
                marker,
                rank.bold(),
                alternative.bold(),
                score.bold(),
                gap
            );
            continue;
        }
        println!(
            "{} {}  {}  {}    {}",
            marker,
            rank,
            alternative,
            score,
            gap.dimmed()
        );
    }

    println!();
    output::item(&format!(
        "{}: {}",
        "criteria".cyan(),
        criteria_summary(matrix).dimmed()
    ));
}

fn column_widths(ranking: &Ranking) -> (usize, usize) {
    let alternative_width = ranking
        .ranked
        .iter()
        .map(|item| item.alternative.len())
        .max()
        .unwrap_or("alternative".len())
        .max("alternative".len());
    let score_width = ranking
        .ranked
        .iter()
        .map(|item| format!("{:.3}", item.score).len())
        .max()
        .unwrap_or("score".len())
        .max("score".len());
    (alternative_width, score_width)
}

fn criteria_summary(matrix: &DecisionMatrix) -> String {
    let weights = matrix.normalized_weights();
    matrix
        .criteria
        .iter()
        .map(|(name, criterion)| {
            format!(
                "{} ({:.2}, {})",
                name,
                weights.get(name).copied().unwrap_or(0.0),
                criterion.direction.as_str()
            )
        })
        .collect::<Vec<_>>()
        .join(" · ")
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

    #[test]
    fn print_styled_with_terminal_category_runs_without_panic() {
        let tmp = tempfile::tempdir().unwrap();
        let decisions = tmp.path().join("kaizen/decisions");
        std::fs::create_dir_all(&decisions).unwrap();
        std::fs::write(decisions.join("terminal.toml"), TERMINAL).unwrap();
        let paths = FixedPaths {
            config: tmp.path().to_owned(),
        };

        assert!(print_styled(Some("terminal"), false, None, &paths, &StdFileSystem).is_ok());
    }
}
