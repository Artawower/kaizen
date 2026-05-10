use std::path::Path;

use anyhow::Result;
use kaizen_core::{ApplyBackend, KaizenEngine, PostApplyBackend, SyncOpts, TargetOs};

use crate::backend::detect_backend;
use owo_colors::OwoColorize;

use crate::{output, reporter::StderrReporter};

pub fn run(engine: &KaizenEngine, config_path: &Path, dry_run: bool) -> Result<()> {
    let os = TargetOs::detect();
    let backend = detect_backend(os);
    run_with(engine, config_path, dry_run, backend.id(), backend.as_ref())
}

fn run_with<B: ApplyBackend + PostApplyBackend + ?Sized>(
    engine: &KaizenEngine,
    config_path: &Path,
    dry_run: bool,
    backend_id: &str,
    backend: &B,
) -> Result<()> {
    output::page_header(if dry_run { "apply  (dry-run)" } else { "apply" });

    let config = engine.load_config(config_path)?;
    output::warn_if_schema_outdated(&config);

    let os = TargetOs::detect();
    let plan = engine.build_workflow_plan(&config, os)?;

    output::kv("backend", backend_id);
    println!();

    let opts = SyncOpts { dry_run, ..Default::default() };

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

    let reporter = StderrReporter;
    let report = backend.apply(&plan, &opts, &reporter)?;
    if let Some(path) = &report.data_path {
        output::item_ok(&format!("wrote {}", path.display()));
    }
    output::item_ok("chezmoi apply done");

    backend.post_apply(&opts, &reporter)?;
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
        ApplyBackend, ApplyReport, KaizenEngine, KaizenError, PostApplyBackend, ProgressReporter,
        SyncOpts, SyncPreview, SyncStep,
    };

    use super::run_with;

    struct SpyApplyBackend {
        apply_called: AtomicBool,
        post_apply_called: AtomicBool,
    }

    impl SpyApplyBackend {
        fn new() -> Self {
            Self {
                apply_called: AtomicBool::new(false),
                post_apply_called: AtomicBool::new(false),
            }
        }
    }

    impl ApplyBackend for SpyApplyBackend {
        fn apply(
            &self,
            _: &kaizen_core::WorkflowPlan,
            _: &SyncOpts,
            _: &dyn ProgressReporter,
        ) -> Result<ApplyReport, KaizenError> {
            self.apply_called.store(true, Ordering::Relaxed);
            Ok(ApplyReport::default())
        }

        fn apply_preview(&self, _: &kaizen_core::WorkflowPlan) -> SyncPreview {
            SyncPreview {
                steps: vec![SyncStep {
                    label: "apply dotfiles".into(),
                    command: "chezmoi apply".into(),
                }],
            }
        }
    }

    impl PostApplyBackend for SpyApplyBackend {
        fn post_apply(&self, _: &SyncOpts, _: &dyn ProgressReporter) -> Result<(), KaizenError> {
            self.post_apply_called.store(true, Ordering::Relaxed);
            Ok(())
        }
    }

    fn fixture_path(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name)
    }

    fn fixture_engine() -> KaizenEngine {
        KaizenEngine::new(
            fixture_path("features"),
            std::sync::Arc::new(crate::filesystem::StdFileSystem),
        )
    }

    #[test]
    fn dry_run_does_not_call_apply() {
        let backend = SpyApplyBackend::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            true,
            "mock",
            &backend,
        )
        .unwrap();
        assert!(!backend.apply_called.load(Ordering::Relaxed));
    }

    #[test]
    fn normal_run_calls_apply_and_post_apply() {
        let backend = SpyApplyBackend::new();
        let engine = fixture_engine();
        run_with(
            &engine,
            &fixture_path("config-minimal.toml"),
            false,
            "mock",
            &backend,
        )
        .unwrap();
        assert!(backend.apply_called.load(Ordering::Relaxed));
        assert!(backend.post_apply_called.load(Ordering::Relaxed));
    }
}
