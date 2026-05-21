; Kaizen Steel prelude — loaded before any module.scm.

; ── Meta-kwarg aliases ────────────────────────────────────────────────────────
; Defined here so they work even without loading features/actions/module.scm.
(define :os          'os)
(define :group       'group)
(define :stability   'stability)
(define :description 'description)
(define :mnemonic    'mnemonic)

; ── declare-module ────────────────────────────────────────────────────────────
(define (declare-module name . kwargs)
  (%declare-module-impl name kwargs))

; ── define-action ─────────────────────────────────────────────────────────────
; Variadic so callers can pass :mnemonic and future kwargs.
(define (define-action id description . kwargs)
  (%define-action-impl id description kwargs))

; ── action-mnemonic ───────────────────────────────────────────────────────────
(define (action-mnemonic action-id)
  (%action-mnemonic-impl action-id))

; ── current-mode + in-mode ────────────────────────────────────────────────────
(define current-mode (make-parameter "normal"))

(define-syntax in-mode
  (syntax-rules ()
    ((_ mode body ...)
     (parameterize ((current-mode (symbol->string 'mode)))
       body ...))))

; ── load-toml-string ───────────────────────────────────────────────────────
; PoC stub — returns the raw TOML string unchanged.
(define (load-toml-string s) s)

; ── render-bindings-toml ────────────────────────────────────────────────────
; bindings — list of (action key mode) triples from get-bindings.
; Returns a TOML snippet with one [keys.MODE] section per mode.
; Pure functional — avoids set-cdr! (Steel uses immutable lists).
(define (render-bindings-toml bindings)
  (define (section mode)
    (let ((blist (filter (lambda (b) (equal? (caddr b) mode)) bindings)))
      (if (null? blist)
          ""
          (string-append
            "[keys." mode "]\n"
            (apply string-append
                   (map (lambda (b)
                          (string-append "\"" (cadr b) "\" = \"" (car b) "\"\n"))
                        blist))
            "\n"))))
  (string-append
    (section "normal")
    (section "insert")
    (section "select")))

; ── bind! ─────────────────────────────────────────────────────────────────────
(define (bind! action key)
  (%bind!-impl
    (if (symbol? action) (symbol->string action) action)
    (if (symbol? key)    (symbol->string key)    key)
    (current-mode)))

; ── rebind! ───────────────────────────────────────────────────────────────────
; User-facing override: rebind action in a specific module.
(define (rebind! module-sym action key)
  (%rebind!-impl
    (if (symbol? module-sym) (symbol->string module-sym) module-sym)
    (if (symbol? action)     (symbol->string action)     action)
    (if (symbol? key)        (symbol->string key)        key)))
