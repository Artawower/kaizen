(require "forest/forest.scm")

(provide forest-toggle)

(forest-configure! 'left #:ignore (list ".git" "target" "__pycache__"))
(forest-set-style! 'snacks)
(forest-snack-circular-keybinds #t)
(forest-set-sidebar-bg! #:focused "#1e1e2e" #:unfocused "#181825")
(forest-set-search-color! #:always "#89b4fa")

(define (forest-toggle)
  (if (forest-snacks-active?)
    (forest-close)
    (forest-open)))

;; Oil

(require "oil/oil.scm")

;; Optional: set defaults (both #false by default)
;; (oil-configure! show-dotfiles show-git-ignored)
(oil-configure! #false #false)

(require "helix/keymaps.scm")

(keymap (global)
  (normal
    (space
      (o
        (o ":oil")
        (e ":oil-enter")
        (b ":oil-up")
        (g ":oil-root")
        (s ":oil-save")
        (r ":oil-refresh")
        (q ":oil-close")
        (h ":oil-toggle-hidden")
        (i ":oil-toggle-git-ignored")
        (m
          (y ":oil-yank")
          (x ":oil-cut")
          (p ":oil-paste")
          (c ":oil-clipboard-clear"))))))
