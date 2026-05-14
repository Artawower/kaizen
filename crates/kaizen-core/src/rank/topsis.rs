use std::cmp::Ordering;

use indexmap::IndexMap;

use crate::rank::{DecisionMatrix, Direction, Ranked, Ranking};
use crate::KaizenError;

pub fn rank(matrix: &DecisionMatrix) -> Result<Ranking, KaizenError> {
    let category = matrix.category_label();
    if matrix.criteria.is_empty() {
        return Err(KaizenError::RankEmpty { category });
    }
    if matrix.alternatives.is_empty() {
        return Err(KaizenError::RankEmpty { category });
    }

    let weight_sum = matrix
        .criteria
        .values()
        .map(|criterion| criterion.weight)
        .sum::<f64>();
    if weight_sum == 0.0 {
        return Err(KaizenError::RankZeroWeights);
    }

    let criteria = matrix.criteria.keys().cloned().collect::<Vec<_>>();
    let alternatives = matrix.alternatives.keys().cloned().collect::<Vec<_>>();
    let weights = matrix.normalized_weights();
    let values = values_by_criterion(matrix, &criteria, &alternatives)?;
    let normalized = normalize_columns(values, &criteria)?;
    let weighted = weight_columns(normalized, &criteria, &weights);
    let (ideal, anti_ideal) = ideals(matrix, &criteria, &weighted);
    let mut ranked = alternatives
        .iter()
        .enumerate()
        .map(|(row, alternative)| {
            let distance_to_ideal = distance(&weighted[row], &ideal);
            let distance_to_anti_ideal = distance(&weighted[row], &anti_ideal);
            let denominator = distance_to_ideal + distance_to_anti_ideal;
            let score = if denominator == 0.0 {
                0.0
            } else {
                distance_to_anti_ideal / denominator
            };
            Ranked {
                rank: 0,
                alternative: alternative.clone(),
                score,
                distance_to_ideal,
                distance_to_anti_ideal,
            }
        })
        .collect::<Vec<_>>();

    ranked.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(Ordering::Equal)
            .then_with(|| left.alternative.cmp(&right.alternative))
    });

    for (idx, item) in ranked.iter_mut().enumerate() {
        item.rank = idx + 1;
    }

    Ok(Ranking { ranked })
}

fn values_by_criterion(
    matrix: &DecisionMatrix,
    criteria: &[String],
    alternatives: &[String],
) -> Result<Vec<Vec<f64>>, KaizenError> {
    let mut rows = vec![vec![0.0; criteria.len()]; alternatives.len()];
    for (row, alternative_name) in alternatives.iter().enumerate() {
        let alternative = &matrix.alternatives[alternative_name];
        for (col, criterion_name) in criteria.iter().enumerate() {
            let score = alternative.scores.get(criterion_name).ok_or_else(|| {
                KaizenError::RankMissingScore {
                    alternative: alternative_name.clone(),
                    criterion: criterion_name.clone(),
                }
            })?;
            rows[row][col] = *score;
        }
    }
    Ok(rows)
}

fn normalize_columns(
    values: Vec<Vec<f64>>,
    criteria: &[String],
) -> Result<Vec<Vec<f64>>, KaizenError> {
    let mut normalized = values.clone();
    for (col, criterion) in criteria.iter().enumerate() {
        let norm = values
            .iter()
            .map(|row| row[col] * row[col])
            .sum::<f64>()
            .sqrt();
        if norm == 0.0 {
            return Err(KaizenError::RankZeroColumn {
                criterion: criterion.clone(),
            });
        }
        for row in &mut normalized {
            row[col] /= norm;
        }
    }
    Ok(normalized)
}

fn weight_columns(
    normalized: Vec<Vec<f64>>,
    criteria: &[String],
    weights: &IndexMap<String, f64>,
) -> Vec<Vec<f64>> {
    let mut weighted = normalized;
    for row in &mut weighted {
        for (col, criterion) in criteria.iter().enumerate() {
            row[col] *= weights[criterion];
        }
    }
    weighted
}

fn ideals(
    matrix: &DecisionMatrix,
    criteria: &[String],
    weighted: &[Vec<f64>],
) -> (Vec<f64>, Vec<f64>) {
    let mut ideal = vec![0.0; criteria.len()];
    let mut anti_ideal = vec![0.0; criteria.len()];
    for (col, criterion_name) in criteria.iter().enumerate() {
        let min = weighted
            .iter()
            .map(|row| row[col])
            .fold(f64::INFINITY, f64::min);
        let max = weighted
            .iter()
            .map(|row| row[col])
            .fold(f64::NEG_INFINITY, f64::max);
        match matrix.criteria[criterion_name].direction {
            Direction::Max => {
                ideal[col] = max;
                anti_ideal[col] = min;
            }
            Direction::Min => {
                ideal[col] = min;
                anti_ideal[col] = max;
            }
        }
    }
    (ideal, anti_ideal)
}

fn distance(row: &[f64], target: &[f64]) -> f64 {
    row.iter()
        .zip(target.iter())
        .map(|(value, ideal)| (value - ideal).powi(2))
        .sum::<f64>()
        .sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rank::{Alternative, Criterion};

    fn criterion(weight: f64, direction: Direction) -> Criterion {
        Criterion {
            weight,
            direction,
            description: None,
        }
    }

    fn alternative(scores: &[(&str, f64)]) -> Alternative {
        Alternative {
            scores: scores
                .iter()
                .map(|(name, score)| ((*name).to_owned(), *score))
                .collect(),
        }
    }

    fn matrix(weights: (f64, f64)) -> DecisionMatrix {
        DecisionMatrix {
            schema_version: 1,
            title: Some("Choice".to_owned()),
            criteria: [
                ("quality".to_owned(), criterion(weights.0, Direction::Max)),
                ("cost".to_owned(), criterion(weights.1, Direction::Min)),
            ]
            .into_iter()
            .collect(),
            alternatives: [
                (
                    "alpha".to_owned(),
                    alternative(&[("quality", 9.0), ("cost", 6.0)]),
                ),
                (
                    "beta".to_owned(),
                    alternative(&[("quality", 7.0), ("cost", 3.0)]),
                ),
            ]
            .into_iter()
            .collect(),
            category: Some("choice".to_owned()),
        }
    }

    #[test]
    fn topsis_classic_example() {
        let matrix = DecisionMatrix {
            schema_version: 1,
            title: Some("Phone".to_owned()),
            criteria: [
                ("price".to_owned(), criterion(0.35, Direction::Min)),
                ("storage".to_owned(), criterion(0.25, Direction::Max)),
                ("camera".to_owned(), criterion(0.25, Direction::Max)),
                ("looks".to_owned(), criterion(0.15, Direction::Max)),
            ]
            .into_iter()
            .collect(),
            alternatives: [
                (
                    "a1".to_owned(),
                    alternative(&[
                        ("price", 250.0),
                        ("storage", 16.0),
                        ("camera", 12.0),
                        ("looks", 5.0),
                    ]),
                ),
                (
                    "a2".to_owned(),
                    alternative(&[
                        ("price", 200.0),
                        ("storage", 16.0),
                        ("camera", 8.0),
                        ("looks", 3.0),
                    ]),
                ),
                (
                    "a3".to_owned(),
                    alternative(&[
                        ("price", 300.0),
                        ("storage", 32.0),
                        ("camera", 16.0),
                        ("looks", 4.0),
                    ]),
                ),
                (
                    "a4".to_owned(),
                    alternative(&[
                        ("price", 275.0),
                        ("storage", 32.0),
                        ("camera", 8.0),
                        ("looks", 4.0),
                    ]),
                ),
            ]
            .into_iter()
            .collect(),
            category: Some("phone".to_owned()),
        };

        let ranking = rank(&matrix).unwrap();

        assert_eq!(ranking.ranked[0].alternative, "a3");
        assert!((ranking.ranked[0].score - 0.629).abs() < 0.001);
    }

    #[test]
    fn topsis_handles_min_direction() {
        let ranking = rank(&matrix((1.0, 2.0))).unwrap();

        assert_eq!(ranking.ranked[0].alternative, "beta");
    }

    #[test]
    fn topsis_normalizes_weights() {
        let ranking_a = rank(&matrix((3.0, 1.5))).unwrap();
        let ranking_b = rank(&matrix((0.667, 0.333))).unwrap();

        assert_eq!(
            ranking_a
                .ranked
                .iter()
                .map(|item| item.alternative.as_str())
                .collect::<Vec<_>>(),
            ranking_b
                .ranked
                .iter()
                .map(|item| item.alternative.as_str())
                .collect::<Vec<_>>()
        );
        assert!((ranking_a.ranked[0].score - ranking_b.ranked[0].score).abs() < 0.001);
    }

    #[test]
    fn topsis_empty_alternatives_errors() {
        let mut matrix = matrix((1.0, 1.0));
        matrix.alternatives.clear();

        assert!(matches!(rank(&matrix), Err(KaizenError::RankEmpty { .. })));
    }

    #[test]
    fn topsis_missing_score_errors() {
        let mut matrix = matrix((1.0, 1.0));
        matrix.alternatives["alpha"].scores.shift_remove("cost");

        assert!(matches!(
            rank(&matrix),
            Err(KaizenError::RankMissingScore { alternative, criterion })
                if alternative == "alpha" && criterion == "cost"
        ));
    }
}
