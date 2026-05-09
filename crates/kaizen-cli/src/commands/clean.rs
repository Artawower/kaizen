use std::path::Path;

use anyhow::Result;
use kaizen_core::{CleanBackend, CleanOpts, KaizenEngine, TargetOs};

use crate::backend::detect_backend;
use owo_colors::OwoColorize;

use crate::output;

pub fn run(engine: &KaizenEngine, config_path: &Path, dry_run: bool) -> Result<()> {
    let os = TargetOs::detect();
    let backend = detect_backend(os);
    run_with(engine, config_path, dry_run, backend.id(), backend.as_ref())
}

fn run_with(
    engine: &KaizenEngine,
    config_path: &Path,
    dry_run: bool,
    backend_id: &str,
    backend: &dyn CleanBackend,
) -> Result<()> {
    output::page_header(if dry_run { "clean  (dry-run)" } else { "clean" });

    let config = engine.load_config(config_path)?;
    let os = TargetOs::detect();
    let plan = engine.build_workflow_plan(&config, os)?;

    output::kv("backend", backend_id);
    println!();

    let report = backend.clean(&CleanOpts { dry_run })?;

    if dry_run {
        output::header("would run");
        for step in &report.steps {
            println!("  {}  {}", "→".dimmed(), step.dimmed());
        }
        println!();
        println!("  Run without --dry-run to clean.");
        let _ = plan;
        return Ok(());
    }

    for step in &report.steps {
        output::item_ok(step);
    }
    if let Some(freed) = report.freed_bytes {
        println!();
        output::item_ok(&format!("freed {:.1} GB", freed as f64 / 1_073_741_824.0));
    }

    println!();
    output::item_ok("clean complete");
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicBool, Ordering};

    use kaizen_core::{CleanBackend, CleanOpts, CleanReport, KaizenEngine, KaizenError};

    use super::run_with;

    struct SpyCleanBackend {
        clean_called: AtomicBool,
        last_dry_run: AtomicBool,
    }

    impl SpyCleanBackend {
        fn new() -> Self {
            Self {
                clean_called: AtomicBool::new(false),
                last_dry_run: AtomicBool::new(false),
            }
        }
    }

    impl CleanBackend for SpyCleanBackend {
        fn clean(&self, opts: &CleanOpts) -> Result<CleanReport, KaizenError> {
            self.clean_called.store(true, Ordering::Relaxed);
            self.last_dry_run.store(opts.dry_run, Ordering::Relaxed);
            Ok(CleanReport {
                freed_bytes: None,
                steps: vec!["mock clean step".into()],
            })
        }
    }

    fn fixture_path(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name)
    }

    fn fixture_engine() -> KaizenEngine {
        KaizenEngine::new(fixture_path("features"))
    }

    #[test]
    fn clean_is_always_called_with_dry_run_flag() {
        let backend = SpyCleanBackend::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            true,
            "mock",
            &backend,
        )
        .unwrap();
        assert!(backend.clean_called.load(Ordering::Relaxed));
        assert!(backend.last_dry_run.load(Ordering::Relaxed));
    }

    #[test]
    fn clean_normal_passes_dry_run_false() {
        let backend = SpyCleanBackend::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            false,
            "mock",
            &backend,
        )
        .unwrap();
        assert!(backend.clean_called.load(Ordering::Relaxed));
        assert!(!backend.last_dry_run.load(Ordering::Relaxed));
    }
}
