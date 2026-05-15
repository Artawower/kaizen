use crate::rank::{DecisionMatrix, Ranking};

pub fn render_md(title: &str, matrix: &DecisionMatrix, ranking: &Ranking) -> String {
    render_md_with_level(title, matrix, ranking, 1)
}

pub fn render_md_section(title: &str, matrix: &DecisionMatrix, ranking: &Ranking) -> String {
    render_md_with_level(title, matrix, ranking, 2)
}

fn render_md_with_level(
    title: &str,
    matrix: &DecisionMatrix,
    ranking: &Ranking,
    level: usize,
) -> String {
    let heading = "#".repeat(level);
    let section = "#".repeat(level + 1);
    let mut out = String::new();

    out.push_str(&format!("{heading} {title}\n\n"));
    out.push_str(&format!("{section} Criteria\n\n"));
    out.push_str("| Criterion | Weight | Direction | Description |\n");
    out.push_str("|-----------|-------:|:---------:|-------------|\n");
    let weights = matrix.normalized_weights();
    for (name, criterion) in &matrix.criteria {
        out.push_str(&format!(
            "| {} | {:.2} | {} | {} |\n",
            name,
            weights.get(name).copied().unwrap_or(0.0),
            criterion.direction.as_str(),
            criterion.description.as_deref().unwrap_or("")
        ));
    }

    out.push_str(&format!("\n{section} Ranking (TOPSIS)\n\n"));
    out.push_str("| Rank | Alternative | Score |\n");
    out.push_str("|-----:|-------------|------:|\n");
    for item in &ranking.ranked {
        out.push_str(&format!(
            "| {} | {} | {:.3} |\n",
            item.rank, item.alternative, item.score
        ));
    }

    out
}

#[cfg(test)]
mod tests {
    use indexmap::IndexMap;

    use super::*;
    use crate::rank::{Alternative, Criterion, Direction, Ranked};

    #[test]
    fn render_md_contains_title_and_ranking() {
        let matrix = DecisionMatrix {
            schema_version: 1,
            title: Some("Terminal".to_owned()),
            criteria: [(
                "speed".to_owned(),
                Criterion {
                    weight: 1.0,
                    direction: Direction::Max,
                    description: Some("Fast startup".to_owned()),
                },
            )]
            .into_iter()
            .collect(),
            alternatives: [(
                "ghostty".to_owned(),
                Alternative {
                    scores: IndexMap::from([("speed".to_owned(), 10.0)]),
                },
            )]
            .into_iter()
            .collect(),
            category: Some("terminal".to_owned()),
        };
        let ranking = Ranking {
            ranked: vec![Ranked {
                rank: 1,
                alternative: "ghostty".to_owned(),
                score: 1.0,
                distance_to_ideal: 0.0,
                distance_to_anti_ideal: 1.0,
            }],
        };

        let output = render_md("Terminal", &matrix, &ranking);

        assert!(output.contains("# Terminal"));
        assert!(output.contains("## Criteria"));
        assert!(output.contains("## Ranking (TOPSIS)"));
        assert!(output.contains("| 1 | ghostty | 1.000 |"));
        assert!(!output.contains("Raw scores"));
    }
}
