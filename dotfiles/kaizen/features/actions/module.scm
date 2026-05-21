; Global action registry.
; Loaded first (alphabetically) before all other feature modules.
;
; Context-key aliases — used with get-context / set-global!
(define :layout        'layout)
(define :ui/font-size  'ui/font-size)
(define :ui/theme      'ui/theme)

; Action ID aliases — :keyword evaluates to its canonical string ID.
; Meta-kwarg aliases (:os :group etc.) are already in kaizen_core.scm prelude.

(define :files/pick    "files/pick")
(define :files/search  "files/search")
(define :vcs/ui        "vcs/ui")
(define :pane/split-v  "pane/split-v")
(define :pane/split-h  "pane/split-h")
(define :project/pick  "project/pick")
(define :nav/left      "nav/left")
(define :nav/right     "nav/right")
(define :nav/up        "nav/up")
(define :nav/down      "nav/down")
(define :wm/focus-left  "wm/focus-left")
(define :wm/focus-right "wm/focus-right")
(define :wm/focus-up    "wm/focus-up")
(define :wm/focus-down  "wm/focus-down")
(define :wm/move-left   "wm/move-left")
(define :wm/move-right  "wm/move-right")

; ── Action declarations ───────────────────────────────────────────────────────
; Actions with mnemonics — the leader key is prepended by each tool.
(define-action :files/pick   "Open file picker"       :mnemonic '("f" "f"))
(define-action :files/search "Global search"          :mnemonic '("f" "g"))
(define-action :vcs/ui       "Open VCS interface"     :mnemonic '("g" "g"))
(define-action :pane/split-v "Split pane vertically"  :mnemonic '("w" "v"))
(define-action :pane/split-h "Split pane horizontally" :mnemonic '("w" "s"))
(define-action :project/pick "Switch project"         :mnemonic '("p" "p"))

; Navigation — no mnemonic; each tool binds to its own layout key.
(define-action :nav/left  "Focus left")
(define-action :nav/right "Focus right")
(define-action :nav/up    "Focus up")
(define-action :nav/down  "Focus down")

; WM actions — bound via global-shortcut hook, not modal bindings.
(define-action :wm/focus-left  "WM focus window left")
(define-action :wm/focus-right "WM focus window right")
(define-action :wm/focus-up    "WM focus window up")
(define-action :wm/focus-down  "WM focus window down")
(define-action :wm/move-left   "WM move window left")
(define-action :wm/move-right  "WM move window right")
