(declare-module "zed"
  :os          '(darwin linux)
  :group       'editor
  :description "Zed GUI editor")

(brew! "zed")
(config-dir! ".")

(define layout (get-context "layout"))

; Provide the gui/editor/bind hook so other modules can inject Zed bindings.
(provide-hook "gui/editor/bind"
  (lambda (action key) (%bind!-impl action key "normal")))

; Default bindings — applied in normal (non-modal) mode.
(bind! :files/pick   "space f f")
(bind! :files/search "space /")
(bind! :vcs/ui       "space g g")
(bind! :pane/split-v "space w v")
(bind! :pane/split-h "space w s")
(bind! :project/pick "space p p")

; Colemak navigation overrides.
(when (equal? layout "colemak")
  (bind! :nav/down  "ctrl-alt-n")
  (bind! :nav/up    "ctrl-alt-e")
  (bind! :nav/right "ctrl-alt-i"))

(on-apply!
  (lambda ()
    (generate-file! "~/.config/zed/keymap.json"
      "stub: render JSON keymap from bindings")))
