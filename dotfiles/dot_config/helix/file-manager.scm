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
