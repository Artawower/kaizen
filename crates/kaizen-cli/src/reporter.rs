use kaizen_core::ProgressReporter;

pub struct StderrReporter;

impl ProgressReporter for StderrReporter {
    fn step(&self, message: &str) {
        eprintln!("{message}");
    }

    fn warn(&self, message: &str) {
        eprintln!("warning: {message}");
    }
}
