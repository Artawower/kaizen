use std::path::Path;

use anyhow::Result;
use kaizen_core::{detect_backend, KaizenEngine, SyncBackend, SyncOpts, TargetOs};
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
    output::page_header(if dry_run { "apply  (dry-run)" } else { "apply" });

    let config = engine.load_config(config_path)?;
    output::warn_if_schema_outdated(&config);

    let os = TargetOs::detect();
    let plan = engine.build_workflow_plan(&config, os)?;

    output::kv("backend", backend.id());
    println!();

    let opts = SyncOpts { dry_run };

    if dry_run {
        let preview = backend.apply_preview(&plan);
        output::header("steps");
        for step in &preview.steps {
            println!("  {}  {}", "→".dimmed(), step.command.dimmed());
        }
        println!();
        println!("  Run without --dry-run to apply.");
        return Ok(());
    }

    let report = backend.apply(&plan, &opts)?;
    if let Some(path) = &report.data_path {
        output::item_ok(&format!("wrote {}", path.display()));
    }
    output::item_ok("chezmoi apply done");

    backend.post_apply(&opts)?;
    output::item_ok("mise install done");

    println!();
    output::item_ok("apply complete");
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicBool, Ordering};

    use kaizen_core::{
        ApplyReport, CleanOpts, CleanReport, InstallReport, KaizenEngine, SyncBackend, SyncOpts,
        SyncPreview, SyncReport, SyncStep, UpdateOpts, UpdateReport, WorkflowPlan,
    };

    use super::run_with;

    struct SpySyncBackend {
        apply_called: AtomicBool,
        post_apply_called: AtomicBool,
    }

    impl SpySyncBackend {
        fn new() -> Self {
            Self {
                apply_called: AtomicBool::new(false),
                post_apply_called: AtomicBool::new(false),
            }
        }
    }

    impl SyncBackend for SpySyncBackend {
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
        ) -> Result<InstallReport, kaizen_core::KaizenError> {
            Ok(InstallReport::default())
        }

        fn apply(
            &self,
            _: &WorkflowPlan,
            _: &SyncOpts,
        ) -> Result<ApplyReport, kaizen_core::KaizenError> {
            self.apply_called.store(true, Ordering::Relaxed);
            Ok(ApplyReport::default())
        }

        fn post_apply(&self, _: &SyncOpts) -> Result<(), kaizen_core::KaizenError> {
            self.post_apply_called.store(true, Ordering::Relaxed);
            Ok(())
        }

        fn sync(
            &self,
            _: &WorkflowPlan,
            _: &SyncOpts,
        ) -> Result<SyncReport, kaizen_core::KaizenError> {
            Ok(SyncReport::default())
        }
        fn update(
            &self,
            _: &WorkflowPlan,
            _: &UpdateOpts,
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
            SyncPreview {
                steps: vec![SyncStep {
                    label: "apply dotfiles".into(),
                    command: "chezmoi apply".into(),
                }],
            }
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
    fn dry_run_does_not_call_apply() {
        let backend = SpySyncBackend::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            true,
            &backend,
        )
        .unwrap();
        assert!(!backend.apply_called.load(Ordering::Relaxed));
    }

    #[test]
    fn normal_run_calls_apply_and_post_apply() {
        let backend = SpySyncBackend::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            false,
            &backend,
        )
        .unwrap();
        assert!(backend.apply_called.load(Ordering::Relaxed));
        assert!(backend.post_apply_called.load(Ordering::Relaxed));
    }
}
