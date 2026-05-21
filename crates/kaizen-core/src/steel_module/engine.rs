use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};

use steel::rerrs::{ErrorKind, SteelErr};
use steel::rvals::SteelVal;
use steel::steel_vm::engine::Engine;
use steel::steel_vm::register_fn::RegisterFn;

use super::state::{
    ActionDecl, BindingDecl, KaizenState, ModuleDecl, PackageDecl, PackageManager, Phase,
};

// ── Per-engine thread-local storage ──────────────────────────────────────────
//
// Each `SteelEngine` is assigned a unique `u64` id at construction.  All
// registered closures capture ONLY that id (which is `Copy + Send + Sync`),
// satisfying steel's `register_fn` trait bounds while guaranteeing that two
// engines on the same thread never share state.
//
// The HashMap lives in a thread-local so `SteelVal` (which is `!Send`) never
// crosses thread boundaries.

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

thread_local! {
    static STATES: RefCell<HashMap<u64, KaizenState>> = RefCell::new(HashMap::new());
}

fn with_state<T>(id: u64, f: impl FnOnce(&KaizenState) -> T) -> T {
    STATES.with(|map| f(map.borrow().get(&id).expect("engine state not found")))
}

fn with_state_mut<T>(id: u64, f: impl FnOnce(&mut KaizenState) -> T) -> T {
    STATES.with(|map| {
        f(map
            .borrow_mut()
            .get_mut(&id)
            .expect("engine state not found"))
    })
}

fn insert_state(id: u64, state: KaizenState) {
    STATES.with(|map| map.borrow_mut().insert(id, state));
}

fn remove_state(id: u64) {
    STATES.with(|map| map.borrow_mut().remove(&id));
}

// ── Engine wrapper ────────────────────────────────────────────────────────────

pub struct SteelEngine {
    /// Underlying Steel VM.  `pub` so tests can call `engine.engine.run(...)`.
    pub engine: Engine,
    id: u64,
}

impl SteelEngine {
    /// Create a fresh engine with its own isolated `KaizenState`.
    pub fn new(context: HashMap<String, String>) -> Self {
        let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
        insert_state(id, KaizenState::default());
        with_state_mut(id, |s| s.initial_context = context.clone());

        let mut engine = Engine::new();
        register_all(&mut engine, id, context);

        engine
            .run(include_str!("kaizen_core.scm").to_owned())
            .expect("kaizen_core.scm failed to load");

        SteelEngine { engine, id }
    }

    /// Read-only access to this engine's state.
    pub fn with_state<T>(&self, f: impl FnOnce(&KaizenState) -> T) -> T {
        with_state(self.id, f)
    }

    /// Mutable access to this engine's state.
    pub fn with_state_mut<T>(&self, f: impl FnOnce(&mut KaizenState) -> T) -> T {
        with_state_mut(self.id, f)
    }

    /// Bindings (including user overrides) that reference undeclared actions.
    pub fn validate_bindings(&self) -> Vec<String> {
        with_state(self.id, |s| {
            s.effective_bindings()
                .into_iter()
                .filter(|b| !s.actions.contains_key(&b.action))
                .map(|b| {
                    format!(
                        "unknown action '{}' in module '{}'",
                        b.action, b.module_name
                    )
                })
                .collect()
        })
    }

    /// Serialize collected state and write it to `path` as pretty-printed JSON.
    pub fn write_runtime_json(&self, path: &std::path::Path) -> Result<(), String> {
        let json = with_state(self.id, |s| s.to_runtime_json());
        let content = serde_json::to_string_pretty(&json).map_err(|e| e.to_string())?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        std::fs::write(path, content).map_err(|e| e.to_string())
    }

    /// Load Steel code from a string (useful in tests and eval contexts).
    pub fn load_module_from_str(&mut self, code: &str, module_name: &str) -> Result<(), String> {
        with_state_mut(self.id, |s| s.current_module = module_name.to_string());
        self.engine
            .run(code.to_owned())
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Load a single `module.scm` file.
    pub fn load_module(&mut self, path: &std::path::Path, module_name: &str) -> Result<(), String> {
        // Canonicalize to absolute so current-module-dir is usable inside on-apply! callbacks.
        let module_dir = path
            .parent()
            .map(|p| p.canonicalize().unwrap_or_else(|_| p.to_path_buf()));
        with_state_mut(self.id, |s| {
            s.current_module = module_name.to_string();
            s.current_module_dir = module_dir.clone();
            if let Some(dir) = module_dir {
                s.module_dirs.insert(module_name.to_string(), dir);
            }
        });
        let code = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
        self.engine.run(code).map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Phase 2: transition to Apply, resolve hooks, run `on-apply!` callbacks.
    pub fn run_apply_phase(&mut self) -> Result<(), String> {
        with_state_mut(self.id, |s| s.phase = Phase::Apply);
        self.resolve_hooks()?;

        // Clone callback list before calling engine methods so no borrow is
        // held when registered closures re-enter the state map.
        let callbacks: Vec<SteelVal> = with_state(self.id, |s| s.apply_callbacks.clone());
        for (i, cb) in callbacks.into_iter().enumerate() {
            let key = format!("*kaizen-apply-cb-{i}*");
            self.engine.register_value(&key, cb);
            self.engine
                .run(format!("({key})"))
                .map_err(|e| e.to_string())?;
        }
        Ok(())
    }

    /// Run all `on-bump!` callbacks.
    pub fn run_bump_phase(&mut self) -> Result<(), String> {
        let callbacks: Vec<SteelVal> = with_state(self.id, |s| s.bump_callbacks.clone());
        for (i, cb) in callbacks.into_iter().enumerate() {
            let key = format!("*kaizen-bump-cb-{i}*");
            self.engine.register_value(&key, cb);
            self.engine
                .run(format!("({key})"))
                .map_err(|e| e.to_string())?;
        }
        Ok(())
    }

    /// Run all `on-update!` callbacks.
    pub fn run_update_phase(&mut self) -> Result<(), String> {
        let callbacks: Vec<SteelVal> = with_state(self.id, |s| s.update_callbacks.clone());
        for (i, cb) in callbacks.into_iter().enumerate() {
            let key = format!("*kaizen-update-cb-{i}*");
            self.engine.register_value(&key, cb);
            self.engine
                .run(format!("({key})"))
                .map_err(|e| e.to_string())?;
        }
        Ok(())
    }

    /// Run all `on-re-add!` callbacks.
    pub fn run_re_add_phase(&mut self) -> Result<(), String> {
        let callbacks: Vec<SteelVal> = with_state(self.id, |s| s.re_add_callbacks.clone());
        for (i, cb) in callbacks.into_iter().enumerate() {
            let key = format!("*kaizen-re-add-cb-{i}*");
            self.engine.register_value(&key, cb);
            self.engine
                .run(format!("({key})"))
                .map_err(|e| e.to_string())?;
        }
        Ok(())
    }

    fn resolve_hooks(&mut self) -> Result<(), String> {
        // Clone everything up front so no borrow is held during engine calls.
        let (providers, consumers) = with_state(self.id, |s| {
            (s.hook_providers.clone(), s.hook_consumers.clone())
        });

        // Pass 1: validate — all consumers must have a provider.
        // Fail before executing anything so the result is all-or-nothing.
        let missing: Vec<String> = consumers
            .iter()
            .filter(|(name, _)| !providers.contains_key(name))
            .map(|(name, _)| name.clone())
            .collect();
        if !missing.is_empty() {
            return Err(format!("missing hook providers: {}", missing.join(", ")));
        }

        // Pass 2: execute — every provider is guaranteed to exist.
        for (hook_name, consumer) in &consumers {
            let provider = providers.get(hook_name).unwrap().clone();
            self.engine.register_value("*hook-provider*", provider);
            self.engine
                .register_value("*hook-consumer*", consumer.clone());
            self.engine
                .run("(*hook-consumer* *hook-provider*)".to_owned())
                .map_err(|e| format!("hook '{hook_name}' failed: {e}"))?;
        }
        Ok(())
    }
}

impl Drop for SteelEngine {
    fn drop(&mut self) {
        remove_state(self.id);
    }
}

// ── Function registration ─────────────────────────────────────────────────────

fn register_all(engine: &mut Engine, id: u64, ctx: HashMap<String, String>) {
    engine.register_fn(
        "%declare-module-impl",
        move |name: String, kwargs: SteelVal| {
            let pairs = parse_plist(kwargs).unwrap_or_default();
            let os = get_string_list(&pairs, "os");
            let group = get_string_opt(&pairs, "group");
            let stability = get_string_opt(&pairs, "stability").unwrap_or_else(|| "stable".into());
            let description = get_string_opt(&pairs, "description").unwrap_or_default();
            with_state_mut(id, |s| {
                s.modules.push(ModuleDecl {
                    name,
                    os,
                    group,
                    stability,
                    description,
                });
            });
        },
    );

    engine.register_fn("provide-hook", move |name: String, handler: SteelVal| {
        with_state_mut(id, |s| {
            s.hook_providers.insert(name, handler);
        });
    });

    engine.register_fn(
        "use-hook",
        move |name: String, consumer: SteelVal| -> Result<SteelVal, SteelErr> {
            if with_state(id, |s| s.phase == Phase::Apply) {
                return Err(SteelErr::new(
                    ErrorKind::Generic,
                    "use-hook cannot be called during apply phase".into(),
                ));
            }
            with_state_mut(id, |s| s.hook_consumers.push((name, consumer)));
            Ok(SteelVal::Void)
        },
    );

    // %define-action-impl — called from (define-action id desc . kwargs)
    engine.register_fn(
        "%define-action-impl",
        move |id_val: SteelVal, description: String, kwargs: SteelVal| {
            let id_str = steel_to_string(&id_val);
            let pairs = parse_plist(kwargs).unwrap_or_default();
            let mnemonic_vec = get_string_list(&pairs, "mnemonic");
            let mnemonic = if mnemonic_vec.is_empty() {
                None
            } else {
                Some(mnemonic_vec)
            };
            with_state_mut(id, |s| {
                s.actions.insert(
                    id_str.clone(),
                    ActionDecl {
                        id: id_str,
                        description,
                        mnemonic,
                    },
                );
            });
        },
    );

    // %action-mnemonic-impl — returns list-of-strings or #f
    engine.register_fn(
        "%action-mnemonic-impl",
        move |id_val: SteelVal| -> SteelVal {
            let id_str = steel_to_string(&id_val);
            with_state(id, |s| {
                s.actions
                    .get(&id_str)
                    .and_then(|a| a.mnemonic.as_ref())
                    .map(|m| {
                        SteelVal::ListV(
                            m.iter()
                                .map(|k| SteelVal::StringV(k.as_str().into()))
                                .collect(),
                        )
                    })
                    .unwrap_or(SteelVal::BoolV(false))
            })
        },
    );

    engine.register_fn(
        "%bind!-impl",
        move |action: SteelVal, key: String, mode: String| {
            let module_name = with_state(id, |s| s.current_module.clone());
            with_state_mut(id, |s| {
                s.bindings.push(BindingDecl {
                    module_name,
                    action: steel_to_string(&action),
                    key,
                    mode,
                });
            });
        },
    );

    engine.register_fn("nix!", move |name: String| {
        with_state_mut(id, |s| {
            s.packages.push(PackageDecl {
                manager: PackageManager::Nix,
                name,
            });
        });
    });
    engine.register_fn("brew!", move |name: String| {
        with_state_mut(id, |s| {
            s.packages.push(PackageDecl {
                manager: PackageManager::Brew,
                name,
            });
        });
    });
    engine.register_fn("mise!", move |name: String| {
        with_state_mut(id, |s| {
            s.packages.push(PackageDecl {
                manager: PackageManager::Mise,
                name,
            });
        });
    });

    engine.register_fn("on-apply!", move |cb: SteelVal| {
        with_state_mut(id, |s| s.apply_callbacks.push(cb));
    });
    engine.register_fn("on-re-add!", move |cb: SteelVal| {
        with_state_mut(id, |s| s.re_add_callbacks.push(cb));
    });
    engine.register_fn("on-bump!", move |cb: SteelVal| {
        with_state_mut(id, |s| s.bump_callbacks.push(cb));
    });
    engine.register_fn("on-update!", move |cb: SteelVal| {
        with_state_mut(id, |s| s.update_callbacks.push(cb));
    });

    // shell! — run a shell command, return stdout as string.
    // Respects dry_run: prints the command but does not execute.
    engine.register_fn("shell!", move |cmd: String| -> Result<SteelVal, SteelErr> {
        let is_dry = with_state(id, |s| {
            s.initial_context
                .get("dry_run")
                .map(|v| v == "true")
                .unwrap_or(false)
        });
        if is_dry {
            println!("[dry-run] shell! {cmd}");
            return Ok(SteelVal::StringV(String::new().into()));
        }
        let output = std::process::Command::new("sh")
            .arg("-c")
            .arg(&cmd)
            .output()
            .map_err(|e| SteelErr::new(ErrorKind::Generic, e.to_string()))?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(SteelErr::new(
                ErrorKind::Generic,
                format!("shell! failed: {cmd}\n{stderr}"),
            ));
        }
        println!("[kaizen] shell! {cmd}");
        Ok(SteelVal::StringV(
            String::from_utf8_lossy(&output.stdout).to_string().into(),
        ))
    });

    // chezmoi-re-add! — run `chezmoi re-add <path>` (respects dry_run).
    engine.register_fn(
        "chezmoi-re-add!",
        move |path: String| -> Result<SteelVal, SteelErr> {
            let expanded = shellexpand::tilde(&path).to_string();
            let is_dry = with_state(id, |s| {
                s.initial_context
                    .get("dry_run")
                    .map(|v| v == "true")
                    .unwrap_or(false)
            });
            if is_dry {
                println!("[dry-run] chezmoi-re-add! {expanded}");
                return Ok(SteelVal::Void);
            }
            println!("[kaizen] chezmoi re-add {expanded}");
            let status = std::process::Command::new("chezmoi")
                .args(["re-add", &expanded])
                .status()
                .map_err(|e| SteelErr::new(ErrorKind::Generic, e.to_string()))?;
            if !status.success() {
                return Err(SteelErr::new(
                    ErrorKind::Generic,
                    format!("chezmoi re-add failed for {expanded}"),
                ));
            }
            Ok(SteelVal::Void)
        },
    );

    // config-dir! — copy all files from the feature directory (minus module.scm /
    // base.toml) into `<chezmoi_source>/dot_config/<feature>/` so chezmoi deploys them.
    engine.register_fn(
        "config-dir!",
        move |rel_path: String| -> Result<SteelVal, SteelErr> {
            let module_dir = with_state(id, |s| s.current_module_dir.clone());
            let Some(module_dir) = module_dir else {
                return Ok(SteelVal::Void);
            };
            let src_dir = if rel_path == "." {
                module_dir.clone()
            } else {
                module_dir.join(&rel_path)
            };
            if !src_dir.exists() {
                return Ok(SteelVal::Void);
            }

            let is_dry = with_state(id, |s| {
                s.initial_context
                    .get("dry_run")
                    .map(|v| v == "true")
                    .unwrap_or(false)
            });
            let feature_name = module_dir
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("unknown")
                .to_string();
            let chezmoi_source =
                with_state(id, |s| s.initial_context.get("chezmoi_source").cloned());
            let dest_base = chezmoi_source
                .map(|cs| {
                    std::path::PathBuf::from(cs)
                        .join("dot_config")
                        .join(&feature_name)
                })
                .unwrap_or_else(|| {
                    std::path::PathBuf::from("dotfiles/dot_config").join(&feature_name)
                });

            let skip = ["module.scm", "base.toml"];
            for entry in std::fs::read_dir(&src_dir)
                .map_err(|e| SteelErr::new(ErrorKind::Generic, e.to_string()))?
            {
                let entry = entry.map_err(|e| SteelErr::new(ErrorKind::Generic, e.to_string()))?;
                let fname = entry.file_name();
                if skip.iter().any(|s| fname == *s) {
                    continue;
                }
                if !entry.file_type().map(|ft| ft.is_file()).unwrap_or(false) {
                    continue;
                }
                let dest = dest_base.join(&fname);
                if is_dry {
                    println!(
                        "[dry-run] config-dir! {} → {}",
                        entry.path().display(),
                        dest.display()
                    );
                } else {
                    std::fs::create_dir_all(&dest_base)
                        .map_err(|e| SteelErr::new(ErrorKind::Generic, e.to_string()))?;
                    std::fs::copy(entry.path(), &dest)
                        .map_err(|e| SteelErr::new(ErrorKind::Generic, e.to_string()))?;
                    println!("[kaizen] config-dir! copied → {}", dest.display());
                }
            }
            Ok(SteelVal::Void)
        },
    );
    engine.register_fn("config-file!", |path: String| {
        println!("[PoC] config-file! {path}");
    });

    // generate-file! — real file write; respects dry_run from initial_context.
    engine.register_fn(
        "generate-file!",
        move |path: String, content: SteelVal| -> Result<SteelVal, SteelErr> {
            let is_dry = with_state(id, |s| {
                s.initial_context
                    .get("dry_run")
                    .map(|v| v == "true")
                    .unwrap_or(false)
            });
            let content_str = match &content {
                SteelVal::StringV(s) => s.to_string(),
                other => {
                    return Err(SteelErr::new(
                        ErrorKind::Generic,
                        format!("generate-file! expects string content, got {other:?}"),
                    ));
                }
            };
            let expanded = shellexpand::tilde(&path).to_string();
            if is_dry {
                println!("[dry-run] generate-file! → {path}");
                return Ok(SteelVal::Void);
            }
            let p = std::path::Path::new(&expanded);
            if let Some(parent) = p.parent() {
                std::fs::create_dir_all(parent)
                    .map_err(|e| SteelErr::new(ErrorKind::Generic, e.to_string()))?;
            }
            std::fs::write(p, &content_str)
                .map_err(|e| SteelErr::new(ErrorKind::Generic, e.to_string()))?;
            println!("[kaizen] generated → {path}");
            Ok(SteelVal::Void)
        },
    );

    // read-file — read a file; relative paths resolved against current module dir.
    engine.register_fn(
        "read-file",
        move |path: String| -> Result<SteelVal, SteelErr> {
            let resolved = if std::path::Path::new(&path).is_absolute() {
                path
            } else {
                let base = with_state(id, |s| {
                    s.current_module_dir
                        .as_ref()
                        .map(|d| d.to_string_lossy().into_owned())
                        .unwrap_or_default()
                });
                if base.is_empty() {
                    path
                } else {
                    format!("{base}/{path}")
                }
            };
            std::fs::read_to_string(&resolved)
                .map(|s| SteelVal::StringV(s.into()))
                .map_err(|e| SteelErr::new(ErrorKind::Generic, e.to_string()))
        },
    );

    // current-module-dir — returns directory of the currently loading module.
    engine.register_fn("current-module-dir", move || -> SteelVal {
        with_state(id, |s| {
            s.current_module_dir
                .as_ref()
                .map(|p| SteelVal::StringV(p.to_string_lossy().into_owned().into()))
                .unwrap_or(SteelVal::BoolV(false))
        })
    });

    // get-bindings — returns list of (action key mode) triples for a module.
    engine.register_fn("get-bindings", move |module: SteelVal| -> SteelVal {
        let name = steel_to_string(&module);
        let rows: Vec<SteelVal> = with_state(id, |s| {
            s.effective_bindings()
                .into_iter()
                .filter(|b| b.module_name == name)
                .map(|b| {
                    let inner: Vec<SteelVal> = vec![
                        SteelVal::StringV(b.action.into()),
                        SteelVal::StringV(b.key.into()),
                        SteelVal::StringV(b.mode.into()),
                    ];
                    SteelVal::ListV(inner.into_iter().collect())
                })
                .collect()
        });
        SteelVal::ListV(rows.into_iter().collect())
    });

    // set-global! / get-context (globals shadow initial_context)
    engine.register_fn("set-global!", move |key: SteelVal, val: SteelVal| {
        let k = steel_to_string(&key).trim_start_matches(':').to_string();
        let v = steel_to_string(&val);
        with_state_mut(id, |s| {
            s.globals.insert(k, v);
        });
    });

    engine.register_fn("get-context", move |key: SteelVal| -> SteelVal {
        let k = steel_to_string(&key).trim_start_matches(':').to_string();
        with_state(id, |s| {
            s.globals
                .get(&k)
                .or_else(|| ctx.get(&k))
                .map(|v| SteelVal::StringV(v.as_str().into()))
                .unwrap_or(SteelVal::BoolV(false))
        })
    });

    // %rebind!-impl — called from (rebind! module action key)
    engine.register_fn(
        "%rebind!-impl",
        move |module: SteelVal, action: SteelVal, key: String| {
            with_state_mut(id, |s| {
                s.overrides.push(BindingDecl {
                    module_name: steel_to_string(&module),
                    action: steel_to_string(&action),
                    key,
                    mode: "normal".to_string(),
                });
            });
        },
    );

    // set-module-config! / get-module-config
    engine.register_fn(
        "set-module-config!",
        move |module: SteelVal, key: SteelVal, val: SteelVal| {
            let m = steel_to_string(&module);
            let k = steel_to_string(&key).trim_start_matches(':').to_string();
            let v = steel_to_string(&val);
            with_state_mut(id, |s| {
                s.module_configs.entry(m).or_default().insert(k, v);
            });
        },
    );

    engine.register_fn(
        "get-module-config",
        move |module: SteelVal, key: SteelVal| -> SteelVal {
            let m = steel_to_string(&module);
            let k = steel_to_string(&key).trim_start_matches(':').to_string();
            with_state(id, |s| {
                s.module_configs
                    .get(&m)
                    .and_then(|cfg| cfg.get(&k))
                    .map(|v| SteelVal::StringV(v.as_str().into()))
                    .unwrap_or(SteelVal::BoolV(false))
            })
        },
    );
}

// ── Plist / SteelVal helpers ──────────────────────────────────────────────────

/// Parse `('key1 val1 'key2 val2 ...)` into `(key, val)` pairs.
/// Leading `:` is stripped from symbol keys for forward-compatibility.
fn parse_plist(val: SteelVal) -> Option<Vec<(String, SteelVal)>> {
    let SteelVal::ListV(list) = val else {
        return Some(vec![]);
    };
    let items: Vec<SteelVal> = list.into_iter().collect();
    let mut pairs = Vec::new();
    let mut i = 0;
    while i + 1 < items.len() {
        let raw_key = steel_to_string(&items[i]);
        let key = raw_key.trim_start_matches(':').to_string();
        pairs.push((key, items[i + 1].clone()));
        i += 2;
    }
    Some(pairs)
}

/// Convert a `SteelVal` to a plain Rust `String`.
pub fn steel_to_string(val: &SteelVal) -> String {
    match val {
        SteelVal::StringV(s) => s.to_string(),
        SteelVal::SymbolV(s) => s.to_string(),
        SteelVal::BoolV(b) => b.to_string(),
        SteelVal::IntV(i) => i.to_string(),
        SteelVal::NumV(n) => n.to_string(),
        SteelVal::ListV(list) => {
            let items: Vec<String> = list.iter().map(steel_to_string).collect();
            format!("({})", items.join(" "))
        }
        SteelVal::Void => String::new(),
        _ => format!("{val:?}"),
    }
}

fn get_string_list(pairs: &[(String, SteelVal)], key: &str) -> Vec<String> {
    pairs
        .iter()
        .find(|(k, _)| k == key)
        .map(|(_, v)| match v {
            SteelVal::ListV(list) => list.iter().map(steel_to_string).collect(),
            other => vec![steel_to_string(other)],
        })
        .unwrap_or_default()
}

fn get_string_opt(pairs: &[(String, SteelVal)], key: &str) -> Option<String> {
    pairs
        .iter()
        .find(|(k, _)| k == key)
        .map(|(_, v)| steel_to_string(v))
}
