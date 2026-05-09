use std::path::Path;

use anyhow::Result;
use kaizen_core::{detect_backend, CleanOpts, KaizenEngine, SyncBackend, TargetOs};
use owo_colors::OwoColorize;

use crate::output;

pub fn run(engine: &KaizenEngine, config_path: &Path, dry_run: bool) -> Result<()> {
    let os = TargetOs::detect();
    let backend = detect_backend(os);
    run_with(engine, config_path, dry_run, backend.as_ref())
}

fn run_with(
    engine: &KaizenEngine,
    config_path: &Path,
    dry_run: bool,
    backend: &dyn SyncBackend,
) -> Result<()> {
    output::page_header(if dry_run { "clean  (dry-run)" } else { "clean" });

    let config = engine.load_config(config_path)?;
    let os = TargetOs::detect();
    let plan = engine.build_workflow_plan(&config, os)?;

    output::kv("backend", backend.id());
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

    use kaizen_core::{
        ApplyReport, CleanOpts, CleanReport, InstallReport, KaizenEngine, ProgressReporter,
        SyncBackend, SyncOpts, SyncPreview, SyncReport, UpdateOpts, UpdateReport, WorkflowPlan,
    };

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

    impl SyncBackend for SpyCleanBackend {
        fn id(&self) -> &'static str {
            "mock"
        }
        fn is_available(&self) -> bool {
            true
        }

        fn install(
            &self,
            _: &WorkflowPlan,
            _: &SyncOpts,
            _: &dyn ProgressReporter,
        ) -> Result<InstallReport, kaizen_core::KaizenError> {
            Ok(InstallReport::default())
        }
        fn apply(
            &self,
            _: &WorkflowPlan,
            _: &SyncOpts,
            _: &dyn ProgressReporter,
        ) -> Result<ApplyReport, kaizen_core::KaizenError> {
            Ok(ApplyReport::default())
        }
        fn post_apply(
            &self,
            _: &SyncOpts,
            _: &dyn ProgressReporter,
        ) -> Result<(), kaizen_core::KaizenError> {
            Ok(())
        }
        fn sync(
            &self,
            _: &WorkflowPlan,
            _: &SyncOpts,
            _: &dyn ProgressReporter,
        ) -> Result<SyncReport, kaizen_core::KaizenError> {
            Ok(SyncReport::default())
        }
        fn update(
            &self,
            _: &WorkflowPlan,
            _: &UpdateOpts,
            _: &dyn ProgressReporter,
        ) -> Result<UpdateReport, kaizen_core::KaizenError> {
            Ok(UpdateReport::default())
        }

        fn clean(&self, opts: &CleanOpts) -> Result<CleanReport, kaizen_core::KaizenError> {
            self.clean_called.store(true, Ordering::Relaxed);
            self.last_dry_run.store(opts.dry_run, Ordering::Relaxed);
            Ok(CleanReport {
                freed_bytes: None,
                steps: vec!["mock clean step".into()],
            })
        }

        fn preview(&self, _: &WorkflowPlan) -> SyncPreview {
            SyncPreview::default()
        }
        fn apply_preview(&self, _: &WorkflowPlan) -> SyncPreview {
            SyncPreview::default()
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
            &backend,
        )
        .unwrap();
        assert!(backend.clean_called.load(Ordering::Relaxed));
        assert!(!backend.last_dry_run.load(Ordering::Relaxed));
    }
}
