pub trait ProgressReporter: Send + Sync {
    fn step(&self, message: &str);
    fn warn(&self, message: &str);
}

pub struct NoopReporter;

impl ProgressReporter for NoopReporter {
    fn step(&self, _: &str) {}
    fn warn(&self, _: &str) {}
}

#[cfg(test)]
pub struct RecordingReporter {
    steps: std::sync::Mutex<Vec<String>>,
    warnings: std::sync::Mutex<Vec<String>>,
}

#[cfg(test)]
impl RecordingReporter {
    pub fn new() -> Self {
        Self {
            steps: std::sync::Mutex::new(vec![]),
            warnings: std::sync::Mutex::new(vec![]),
        }
    }

    pub fn steps(&self) -> Vec<String> {
        self.steps.lock().unwrap().clone()
    }

    pub fn warnings(&self) -> Vec<String> {
        self.warnings.lock().unwrap().clone()
    }
}

#[cfg(test)]
impl ProgressReporter for RecordingReporter {
    fn step(&self, message: &str) {
        self.steps.lock().unwrap().push(message.to_owned());
    }

    fn warn(&self, message: &str) {
        self.warnings.lock().unwrap().push(message.to_owned());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recording_reporter_captures_steps() {
        let r = RecordingReporter::new();
        r.step("→ chezmoi apply");
        r.step("→ mise install");
        assert_eq!(r.steps(), vec!["→ chezmoi apply", "→ mise install"]);
        assert!(r.warnings().is_empty());
    }

    #[test]
    fn recording_reporter_captures_warnings() {
        let r = RecordingReporter::new();
        r.warn("features not found");
        assert_eq!(r.warnings(), vec!["features not found"]);
        assert!(r.steps().is_empty());
    }

    #[test]
    fn noop_reporter_does_not_panic() {
        let r = NoopReporter;
        r.step("anything");
        r.warn("anything");
    }
}
