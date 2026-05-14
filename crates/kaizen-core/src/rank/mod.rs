pub mod format;
pub mod matrix;
pub mod store;
pub mod topsis;

pub use matrix::{Alternative, Criterion, DecisionMatrix, Direction, Ranked, Ranking};
pub use store::load_decisions_dir;
pub use topsis::rank;
