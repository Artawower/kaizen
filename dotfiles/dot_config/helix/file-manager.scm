(require "forest/forest.scm")

;; Optional: which side the tree renders on ('left by default), and which
;; entry names are always hidden
(forest-configure! 'left #:ignore (list ".git" "target" "__pycache__"))

;; Optional: which explorer UI forest-open uses ('snacks by default)
;; (forest-set-style! style)
(forest-set-style! 'snacks) ; or 'mini

;; Optional (snacks): wrapping j/k inside a folder, and h/l to enter or leave
(forest-snack-circular-keybinds #t)

;; Optional (snacks): give the sidebar its own background per focus state, so the
;; tree stands apart from the buffer.
(forest-set-sidebar-bg! #:focused "#1e1e2e" #:unfocused "#181825")

;; Optional (snacks): color the search box outline. It marks focus by default
;; (orange focused, white unfocused); override the colors, or stop it changing.
(forest-set-search-color! #:focused "#89b4fa" #:unfocused "#585b70")
(forest-set-search-color! #:always "#89b4fa") ; one color, both states
(forest-set-search-color! #:focused "#89b4fa" #:follow-focus? #f) ; never changes
