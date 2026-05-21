(declare-module "yabai"
  :os          '(darwin)
  :group       'tiling-wm
  :description "Yabai tiling WM")

(brew! "koekeishiya/formulae/yabai")
(config-dir! ".")

(define layout (get-context "layout"))

; Return the nav key for dir ('left 'right 'up 'down) under the active layout.
(define (nav-key dir)
  (define colemak? (equal? layout "colemak"))
  (cond
    ((eq? dir 'left)  (if colemak? "h" "h"))
    ((eq? dir 'down)  (if colemak? "n" "j"))
    ((eq? dir 'up)    (if colemak? "e" "k"))
    ((eq? dir 'right) (if colemak? "i" "l"))
    (else "?")))

(use-hook "global-shortcut"
  (lambda (register)
    (register :wm/focus-left
              (string-append "ralt + rshift - " (nav-key 'left))
              "/opt/homebrew/bin/yabai -m window --focus west")
    (register :wm/focus-right
              (string-append "ralt + rshift - " (nav-key 'right))
              "/opt/homebrew/bin/yabai -m window --focus east")
    (register :wm/focus-up
              (string-append "ralt + rshift - " (nav-key 'up))
              "/opt/homebrew/bin/yabai -m window --focus north")
    (register :wm/focus-down
              (string-append "ralt + rshift - " (nav-key 'down))
              "/opt/homebrew/bin/yabai -m window --focus south")
    (register :wm/move-left
              (string-append "ralt + rshift + lcmd - " (nav-key 'left))
              "/opt/homebrew/bin/yabai -m window --warp west")
    (register :wm/move-right
              (string-append "ralt + rshift + lcmd - " (nav-key 'right))
              "/opt/homebrew/bin/yabai -m window --warp east")))
