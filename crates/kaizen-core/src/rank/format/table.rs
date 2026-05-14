use crate::rank::{DecisionMatrix, Ranking};

pub fn render_table(title: &str, matrix: &DecisionMatrix, ranking: &Ranking) -> String {
    let mut out = String::new();
    let top_score = ranking.ranked.first().map(|item| item.score).unwrap_or(0.0);
    let line = "─".repeat(37);

    out.push_str(title);
    out.push('\n');
    out.push_str(&line);
    out.push('\n');
    out.push_str(" #  alternative   score   gap\n");
    for item in &ranking.ranked {
        let gap = if item.rank == 1 {
            "—".to_owned()
        } else {
            format!("{:.3}", item.score - top_score).replace('-', "−")
        };
        out.push_str(&format!(
            "{:>2}  {:<12}  {:.3}   {}\n",
            item.rank, item.alternative, item.score, gap
        ));
    }
    out.push_str(&line);
    out.push('\n');
    out.push_str("criteria: ");
    out.push_str(&criteria_summary(matrix));
    out.push('\n');
    out
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
        .join(", ")
}

#[cfg(test)]
mod tests {
    use indexmap::IndexMap;

    use super::*;
    use crate::rank::{Alternative, Criterion, Direction, Ranked};

    #[test]
    fn render_table_shows_top_first() {
        let matrix = DecisionMatrix {
            schema_version: 1,
            title: Some("Terminal".to_owned()),
            criteria: [("speed".to_owned(), criterion())].into_iter().collect(),
            alternatives: [("ghostty".to_owned(), alternative(10.0))]
                .into_iter()
                .collect(),
            category: Some("terminal".to_owned()),
        };
        let ranking = Ranking {
            ranked: vec![ranked(1, "ghostty", 0.842), ranked(2, "wezterm", 0.711)],
        };

        let output = render_table("Terminal", &matrix, &ranking);

        assert!(output.contains("Terminal"));
        assert!(output.contains(" 1  ghostty"));
        assert!(output.find("ghostty").unwrap() < output.find("wezterm").unwrap());
    }

    fn criterion() -> Criterion {
        Criterion {
            weight: 1.0,
            direction: Direction::Max,
            description: None,
        }
    }

    fn alternative(score: f64) -> Alternative {
        Alternative {
            scores: IndexMap::from([("speed".to_owned(), score)]),
        }
    }

    fn ranked(rank: usize, alternative: &str, score: f64) -> Ranked {
        Ranked {
            rank,
            alternative: alternative.to_owned(),
            score,
            distance_to_ideal: 0.0,
            distance_to_anti_ideal: 0.0,
        }
    }
}
