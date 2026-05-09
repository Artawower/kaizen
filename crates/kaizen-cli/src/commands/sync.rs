use std::path::Path;

use anyhow::Result;
use kaizen_core::{KaizenEngine, SyncBackend, SyncOpts, TargetOs};

use crate::backend::detect_backend;

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
        ApplyBackend, ApplyReport, CleanBackend, CleanOpts, CleanReport, InstallBackend,
        InstallReport, KaizenEngine, KaizenError, PostApplyBackend, PreviewBackend,
        ProgressReporter, SyncBackend, SyncOpts, SyncPreview, SyncReport, UpdateBackend,
        UpdateOpts, UpdateReport, WorkflowPlan,
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
        fn sync(
            &self,
            _: &WorkflowPlan,
            _: &SyncOpts,
            _: &dyn ProgressReporter,
        ) -> Result<SyncReport, KaizenError> {
            self.sync_called.store(true, Ordering::Relaxed);
            Ok(SyncReport::default())
        }
    }

    impl InstallBackend for RecordingSyncBackend {
        fn install(
            &self,
            _: &WorkflowPlan,
            _: &SyncOpts,
            _: &dyn ProgressReporter,
        ) -> Result<InstallReport, KaizenError> {
            Ok(InstallReport::default())
        }
    }

    impl PostApplyBackend for RecordingSyncBackend {
        fn post_apply(&self, _: &SyncOpts, _: &dyn ProgressReporter) -> Result<(), KaizenError> {
            Ok(())
        }
    }

    impl ApplyBackend for RecordingSyncBackend {
        fn apply(
            &self,
            _: &WorkflowPlan,
            _: &SyncOpts,
            _: &dyn ProgressReporter,
        ) -> Result<ApplyReport, KaizenError> {
            Ok(ApplyReport::default())
        }
        fn apply_preview(&self, _: &WorkflowPlan) -> SyncPreview {
            SyncPreview::default()
        }
    }

    impl UpdateBackend for RecordingSyncBackend {
        fn update(
            &self,
            _: &WorkflowPlan,
            _: &UpdateOpts,
            _: &dyn ProgressReporter,
        ) -> Result<UpdateReport, KaizenError> {
            Ok(UpdateReport::default())
        }
    }

    impl CleanBackend for RecordingSyncBackend {
        fn clean(&self, _: &CleanOpts) -> Result<CleanReport, KaizenError> {
            Ok(CleanReport::default())
        }
    }

    impl PreviewBackend for RecordingSyncBackend {
        fn preview(&self, _: &WorkflowPlan) -> SyncPreview {
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
