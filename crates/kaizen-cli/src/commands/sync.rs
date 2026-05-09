use std::path::Path;

use anyhow::Result;
use kaizen_core::{detect_backend, KaizenEngine, SyncBackend, SyncOpts, TargetOs};

use crate::{output, reporter::StderrReporter};

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
    output::page_header(if dry_run { "sync  (dry-run)" } else { "sync" });

    let config = engine.load_config(config_path)?;
    output::warn_if_schema_outdated(&config);

    let os = TargetOs::detect();
    let plan = engine.build_workflow_plan(&config, os)?;

    output::kv("backend", backend.id());
    println!();

    if dry_run {
        let preview = backend.preview(&plan);
        output::header("steps");
        for step in &preview.steps {
            println!("  {:<25} {}", step.label, step.command);
        }
        println!();
        println!("  Run without --dry-run to apply.");
        return Ok(());
    }

    backend.sync(&plan, &SyncOpts { dry_run: false }, &StderrReporter)?;

    println!();
    output::item_ok("sync complete");
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

    struct RecordingSyncBackend {
        sync_called: AtomicBool,
    }

    impl RecordingSyncBackend {
        fn new() -> Self {
            Self {
                sync_called: AtomicBool::new(false),
            }
        }
    }

    impl SyncBackend for RecordingSyncBackend {
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
            self.sync_called.store(true, Ordering::Relaxed);
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
        fn clean(&self, _: &CleanOpts) -> Result<CleanReport, kaizen_core::KaizenError> {
            Ok(CleanReport::default())
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
    fn dry_run_does_not_call_backend_sync() {
        let backend = RecordingSyncBackend::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            true,
            &backend,
        )
        .unwrap();
        assert!(!backend.sync_called.load(Ordering::Relaxed));
    }

    #[test]
    fn normal_run_calls_backend_sync() {
        let backend = RecordingSyncBackend::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            false,
            &backend,
        )
        .unwrap();
        assert!(backend.sync_called.load(Ordering::Relaxed));
    }
}
