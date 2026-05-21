use super::engine::{steel_to_string, SteelEngine};
use super::state::Phase;

// ── helpers ───────────────────────────────────────────────────────────────────

fn fresh() -> SteelEngine {
    SteelEngine::new(Default::default())
}

/// Run Steel code; panic with the source snippet on failure.
fn run(engine: &mut SteelEngine, code: &str) {
    engine.engine.run(code.to_owned()).expect(code);
}

// ── positive tests ────────────────────────────────────────────────────────────

#[test]
fn declare_module_collected() {
    let mut e = fresh();
    // kwargs use quoted symbols as keys (Steel does not auto-quote :symbol)
    run(
        &mut e,
        r#"(declare-module "helix" 'group "editor" 'os '("darwin" "linux") 'stability "stable")"#,
    );
    e.with_state(|s| {
        assert_eq!(s.modules.len(), 1);
        let m = &s.modules[0];
        assert_eq!(m.name, "helix");
        assert_eq!(m.group.as_deref(), Some("editor"));
        assert_eq!(m.os, vec!["darwin", "linux"]);
        assert_eq!(m.stability, "stable");
    });
}

#[test]
fn define_action_and_bind() {
    let mut e = fresh();
    run(
        &mut e,
        r#"
(define-action "helix/open" "Open a file")
(bind! "helix/open" "space-f-f")
"#,
    );
    e.with_state(|s| {
        assert!(
            s.actions.contains_key("helix/open"),
            "action must be declared"
        );
        assert_eq!(s.bindings.len(), 1);
        assert_eq!(s.bindings[0].action, "helix/open");
        assert_eq!(s.bindings[0].key, "space-f-f");
        assert_eq!(s.bindings[0].mode, "normal");
    });
}

#[test]
fn in_mode_sets_binding_mode() {
    let mut e = fresh();
    run(
        &mut e,
        r#"
(define-action "helix/insert-char" "Insert char")
(in-mode insert
  (bind! "helix/insert-char" "a"))
"#,
    );
    e.with_state(|s| {
        assert_eq!(s.bindings.len(), 1);
        assert_eq!(s.bindings[0].mode, "insert");
    });
}

#[test]
fn packages_collected() {
    let mut e = fresh();
    run(
        &mut e,
        r#"
(nix! "helix")
(brew! "ripgrep")
(mise! "node@20")
"#,
    );
    e.with_state(|s| assert_eq!(s.packages.len(), 3));
}

#[test]
fn hook_resolve_calls_consumer_with_provider() {
    let mut e = fresh();
    run(
        &mut e,
        r#"
(provide-hook "theme" (lambda () "dark"))
(define result #f)
(use-hook "theme" (lambda (provider) (set! result (provider))))
"#,
    );
    e.run_apply_phase().expect("apply phase must succeed");
    let vals = e
        .engine
        .run("result".to_owned())
        .expect("result must be defined");
    assert_eq!(vals.last().map(|v| steel_to_string(v)), Some("dark".into()));
}

#[test]
fn on_apply_callback_runs_in_apply_phase() {
    let mut e = fresh();
    run(
        &mut e,
        r#"
(define touched #f)
(on-apply! (lambda () (set! touched #t)))
"#,
    );
    e.run_apply_phase().expect("apply phase must succeed");
    let vals = e
        .engine
        .run("touched".to_owned())
        .expect("touched must be defined");
    match vals.last() {
        Some(steel::rvals::SteelVal::BoolV(true)) => {}
        other => panic!("expected #t, got {other:?}"),
    }
}

// ── isolation: two engines on the same thread must not share state ────────────

#[test]
fn two_engines_do_not_share_state() {
    let mut e1 = fresh();
    let mut e2 = fresh();

    run(&mut e1, r#"(declare-module "only-in-e1" 'group "editor")"#);
    run(&mut e2, r#"(declare-module "only-in-e2" 'group "tools")"#);

    e1.with_state(|s| {
        assert_eq!(s.modules.len(), 1);
        assert_eq!(
            s.modules[0].name, "only-in-e1",
            "e1 must not see e2 modules"
        );
    });
    e2.with_state(|s| {
        assert_eq!(s.modules.len(), 1);
        assert_eq!(
            s.modules[0].name, "only-in-e2",
            "e2 must not see e1 modules"
        );
    });
}

// ── negative tests ────────────────────────────────────────────────────────────

#[test]
fn use_hook_in_apply_phase_errors() {
    let mut e = fresh();
    e.with_state_mut(|s| s.phase = Phase::Apply);
    let result = e
        .engine
        .run(r#"(use-hook "some-hook" (lambda (x) x))"#.to_owned());
    assert!(result.is_err(), "use-hook must fail during Apply phase");
}

#[test]
fn missing_hook_provider_fails_apply_phase() {
    let mut e = fresh();
    // Register a consumer but no provider — apply phase must fail.
    run(&mut e, r#"(use-hook "missing-hook" (lambda (p) p))"#);
    let result = e.run_apply_phase();
    assert!(
        result.is_err(),
        "apply phase must fail when provider is absent"
    );
    let msg = result.unwrap_err();
    assert!(
        msg.contains("missing-hook"),
        "error message must name the missing hook, got: {msg}"
    );
}

#[test]
fn resolve_hooks_is_atomic_no_partial_execution() {
    // hook-a has provider + consumer.
    // hook-missing has consumer but NO provider.
    // Expected: apply fails, hook-a consumer never runs.
    let mut e = fresh();
    run(
        &mut e,
        r#"
(define hook-a-fired #f)
(provide-hook "hook-a" (lambda () "value-a"))
(use-hook "hook-a"       (lambda (p) (set! hook-a-fired #t)))
(use-hook "hook-missing" (lambda (p) p))
"#,
    );
    let result = e.run_apply_phase();
    assert!(result.is_err(), "apply phase must fail on missing provider");
    let msg = result.unwrap_err();
    assert!(
        msg.contains("hook-missing"),
        "error must name the missing hook, got: {msg}"
    );
    // hook-a consumer must NOT have run — no partial execution.
    let vals = e
        .engine
        .run("hook-a-fired".to_owned())
        .expect("hook-a-fired must be defined");
    match vals.last() {
        Some(steel::rvals::SteelVal::BoolV(false)) => {}
        other => panic!("hook-a consumer must not have fired, got {other:?}"),
    }
}

// ── P.3 mnemonic ─────────────────────────────────────────────────────────────

// ── P.3 mnemonic ─────────────────────────────────────────────────────────────

#[test]
fn action_mnemonic_stored_and_retrieved() {
    let mut e = fresh();
    run(
        &mut e,
        r#"(define-action "editor/open" "Open file" 'mnemonic '("f" "f"))"#,
    );
    e.with_state(|s| {
        let a = s.actions.get("editor/open").expect("action must exist");
        assert_eq!(a.mnemonic, Some(vec!["f".to_string(), "f".to_string()]));
    });
}

#[test]
fn action_without_mnemonic_returns_none() {
    let mut e = fresh();
    run(&mut e, r#"(define-action "bare/action" "No mnemonic")"#);
    e.with_state(|s| {
        let a = s.actions.get("bare/action").expect("action must exist");
        assert_eq!(a.mnemonic, None);
    });
}

// ── P.7 colon-prefix kwargs ───────────────────────────────────────────────────

#[test]
fn declare_module_with_colon_prefix_kwargs() {
    let mut e = fresh();
    // :group / :os / :stability are defined in the kaizen_core.scm prelude.
    e.load_module_from_str(
        r#"(declare-module "vim" :group 'editor :os '(linux) :stability 'experimental)"#,
        "vim",
    )
    .unwrap();
    let (group, stability) =
        e.with_state(|s| (s.modules[0].group.clone(), s.modules[0].stability.clone()));
    assert_eq!(group, Some("editor".to_string()));
    assert_eq!(stability, "experimental");
}

#[test]
fn bind_with_unknown_action_flagged_by_validate() {
    let mut e = fresh();
    // bind! without a matching define-action
    run(&mut e, r#"(bind! "ghost/action" "ctrl-g")"#);
    let errors = e.validate_bindings();
    assert_eq!(errors.len(), 1);
    assert!(
        errors[0].contains("ghost/action"),
        "error must mention the unknown action, got: {}",
        errors[0]
    );
}

#[test]
fn validate_bindings_catches_unknown_action_in_override() {
    let mut e = fresh();
    e.load_module_from_str(
        r#"
(declare-module "helix" :group "editor")
(define-action "vcs/ui" "VCS UI")
(bind! "vcs/ui" "space g g")
"#,
        "helix",
    )
    .unwrap();
    // Override references a non-existent action — must be caught by validate.
    e.load_module_from_str(r#"(rebind! "helix" "ghost/action" "ctrl-x")"#, "user")
        .unwrap();
    let errors = e.validate_bindings();
    assert_eq!(errors.len(), 1);
    assert!(
        errors[0].contains("ghost/action"),
        "error must name the unknown action, got: {}",
        errors[0]
    );
}

// ── P.4: set-global! / get-context ──────────────────────────────────────────────────

#[test]
fn set_global_readable_via_get_context() {
    let mut e = fresh();
    // Use string keys in unit tests — :keyword aliases live in actions/module.scm
    run(&mut e, r#"(set-global! "layout" "colemak")"#);
    let vals = e
        .engine
        .run(r#"(get-context "layout")"#.to_owned())
        .unwrap();
    match vals.last() {
        Some(steel::rvals::SteelVal::StringV(s)) => assert_eq!(s.as_str(), "colemak"),
        other => panic!("expected StringV, got {other:?}"),
    }
}

#[test]
fn initial_context_is_fallback_for_get_context() {
    let ctx = std::collections::HashMap::from([("theme".to_string(), "dark".to_string())]);
    let mut e = SteelEngine::new(ctx);
    let vals = e.engine.run(r#"(get-context "theme")"#.to_owned()).unwrap();
    match vals.last() {
        Some(steel::rvals::SteelVal::StringV(s)) => assert_eq!(s.as_str(), "dark"),
        other => panic!("expected StringV, got {other:?}"),
    }
}

#[test]
fn global_shadows_initial_context() {
    let ctx = std::collections::HashMap::from([("layout".to_string(), "qwerty".to_string())]);
    let mut e = SteelEngine::new(ctx);
    run(&mut e, r#"(set-global! "layout" "colemak")"#);
    let vals = e
        .engine
        .run(r#"(get-context "layout")"#.to_owned())
        .unwrap();
    match vals.last() {
        Some(steel::rvals::SteelVal::StringV(s)) => assert_eq!(s.as_str(), "colemak"),
        other => panic!("expected StringV \"colemak\", got {other:?}"),
    }
}

// ── P.5: to_runtime_json ──────────────────────────────────────────────────────────

#[test]
fn runtime_json_contains_modules_actions_bindings() {
    let mut e = fresh();
    // Use load_module_from_str so current_module is set before bind! runs.
    e.load_module_from_str(
        r#"
(declare-module "mymod" :group "tools")
(define-action "mymod/open" "Open" :mnemonic '("o"))
(bind! "mymod/open" "ctrl-o")
"#,
        "mymod",
    )
    .unwrap();
    let json = e.with_state(|s| s.to_runtime_json());
    assert!(
        json["modules"]["mymod"].is_object(),
        "module must appear in JSON"
    );
    assert!(
        json["actions"]["mymod/open"].is_object(),
        "action must appear in JSON"
    );
    assert_eq!(json["actions"]["mymod/open"]["mnemonic"][0], "o");
    assert_eq!(json["modules"]["mymod"]["bindings"]["mymod/open"], "ctrl-o");
}

// ── P.6: rebind! / module-config / user-overrides ──────────────────────────────

#[test]
fn rebind_adds_to_overrides() {
    let mut e = fresh();
    run(&mut e, r#"(rebind! 'helix "helix/open" "ctrl-p")"#);
    e.with_state(|s| {
        assert_eq!(s.overrides.len(), 1);
        assert_eq!(s.overrides[0].module_name, "helix");
        assert_eq!(s.overrides[0].action, "helix/open");
        assert_eq!(s.overrides[0].key, "ctrl-p");
    });
}

#[test]
fn module_config_round_trip() {
    let mut e = fresh();
    run(
        &mut e,
        r#"
(set-module-config! 'helix "leader" ",")
(set-module-config! 'helix "theme"  "dark")
"#,
    );
    let vals = e
        .engine
        .run(r#"(get-module-config 'helix "leader")"#.to_owned())
        .unwrap();
    match vals.last() {
        Some(steel::rvals::SteelVal::StringV(s)) => assert_eq!(s.as_str(), ","),
        other => panic!("expected StringV ',', got {other:?}"),
    }
    e.with_state(|s| {
        assert_eq!(s.module_configs["helix"]["theme"], "dark");
    });
}

#[test]
fn load_user_overrides_nonexistent_dir_is_noop() {
    use crate::steel_module::loader::load_user_overrides;
    let mut e = fresh();
    let result = load_user_overrides(&mut e, std::path::Path::new("/tmp/__no_such_kaizen_dir"));
    assert!(
        result.is_ok(),
        "non-existent dir must not be an error: {result:?}"
    );
}

// ── HIGH: effective_bindings ──────────────────────────────────────────────────────

#[test]
fn effective_bindings_override_replaces_default() {
    let mut e = fresh();
    e.load_module_from_str(
        r#"
(declare-module "helix" :group "editor")
(define-action "vcs/ui" "VCS UI")
(bind! "vcs/ui" "space g g")
"#,
        "helix",
    )
    .unwrap();
    // Apply an override in a second load (simulating user/overrides.scm).
    e.load_module_from_str(
        r#"(rebind! "helix" "vcs/ui" "space o o")"#,
        "user-overrides",
    )
    .unwrap();
    let effective = e.with_state(|s| s.effective_bindings());
    let vcs = effective
        .iter()
        .find(|b| b.action == "vcs/ui")
        .expect("vcs/ui binding must exist");
    assert_eq!(vcs.key, "space o o", "override must win over default");
    // Default bindings slice must be unchanged.
    e.with_state(|s| {
        let default_key = s
            .bindings
            .iter()
            .find(|b| b.action == "vcs/ui")
            .map(|b| b.key.as_str());
        assert_eq!(
            default_key,
            Some("space g g"),
            "defaults must stay untouched"
        );
    });
}

#[test]
fn effective_bindings_appends_unmatched_override() {
    let mut e = fresh();
    e.load_module_from_str(
        r#"
(declare-module "helix" :group "editor")
(define-action "files/pick" "Open file")
(bind! "files/pick" "space f f")
"#,
        "helix",
    )
    .unwrap();
    // Override a binding that doesn't exist in defaults.
    e.load_module_from_str(
        r#"(rebind! "helix" "new/action" "ctrl-n")"#,
        "user-overrides",
    )
    .unwrap();
    let effective = e.with_state(|s| s.effective_bindings());
    assert!(
        effective
            .iter()
            .any(|b| b.action == "new/action" && b.key == "ctrl-n"),
        "unmatched override must be appended"
    );
}

// ── MEDIUM: initial_context in runtime.json ──────────────────────────────────

#[test]
fn runtime_json_context_merges_initial_and_globals() {
    let ctx = std::collections::HashMap::from([("os".to_string(), "darwin".to_string())]);
    let mut e = SteelEngine::new(ctx);
    run(&mut e, r#"(set-global! "layout" "colemak")"#);
    let json = e.with_state(|s| s.to_runtime_json());
    assert_eq!(
        json["context"]["os"], "darwin",
        "initial_context must appear"
    );
    assert_eq!(json["context"]["layout"], "colemak", "globals must appear");
}

#[test]
fn runtime_json_globals_shadow_initial_context() {
    let ctx = std::collections::HashMap::from([("layout".to_string(), "qwerty".to_string())]);
    let mut e = SteelEngine::new(ctx);
    run(&mut e, r#"(set-global! "layout" "colemak")"#);
    let json = e.with_state(|s| s.to_runtime_json());
    assert_eq!(
        json["context"]["layout"], "colemak",
        "global must shadow initial"
    );
}
