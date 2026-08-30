(require "helix/configuration.scm")
(require "helix/keymaps.scm")
(require (only-in "helix/ext.scm" evalp eval-buffer))

(keymap (global)
  (normal
    (space
      (n
        (C ":nrepl-connect")
        (D ":nrepl-disconnect")
        (J ":nrepl-jack-in")
        (L ":nrepl-load-file")
        (S ":nrepl-stdin")
        (b ":nrepl-eval-buffer")
        (i ":nrepl-interrupt")
        (l ":nrepl-lookup")
        (m ":nrepl-eval-multiple-selections")
        (p ":nrepl-eval-prompt")
        (s ":nrepl-eval-selection")))
    (A-ret ":nrepl-eval-selection"))
  (select
    (space
      (n
        (C ":nrepl-connect")
        (D ":nrepl-disconnect")
        (J ":nrepl-jack-in")
        (L ":nrepl-load-file")
        (S ":nrepl-stdin")
        (b ":nrepl-eval-buffer")
        (i ":nrepl-interrupt")
        (l ":nrepl-lookup")
        (m ":nrepl-eval-multiple-selections")
        (p ":nrepl-eval-prompt")
        (s ":nrepl-eval-selection")))
    (A-ret ":nrepl-eval-selection")))

(keymap (global)
  (normal
    (space
      (>
        (s ":slurp-forward")
        (b ":barf-forward")
        (e ":drag-element-forward")
        (f ":drag-form-forward")
        (p ":drag-pair-forward")
        (r ":raise-form")
        (R ":raise-element")
        (x ":splice-form")
        (S ":paredit-split")
        (j ":paredit-join"))
      (<
        (s ":slurp-backward")
        (b ":barf-backward")
        (e ":drag-element-backward")
        (f ":drag-form-backward")
        (p ":drag-pair-backward")
        (r ":raise-form")
        (R ":raise-element")
        (x ":splice-form")
        (S ":paredit-split")
        (j ":paredit-join"))))
  (select
    (space
      (>
        (s ":slurp-forward")
        (b ":barf-forward")
        (e ":drag-element-forward")
        (f ":drag-form-forward")
        (p ":drag-pair-forward")
        (r ":raise-form")
        (R ":raise-element")
        (x ":splice-form")
        (S ":paredit-split")
        (j ":paredit-join"))
      (<
        (s ":slurp-backward")
        (b ":barf-backward")
        (e ":drag-element-backward")
        (f ":drag-form-backward")
        (p ":drag-pair-backward")
        (r ":raise-form")
        (R ":raise-element")
        (x ":splice-form")
        (S ":paredit-split")
        (j ":paredit-join")))))

(define-lsp "steel-language-server" (command "steel-language-server") (args '()))
(define-language "scheme"
  (formatter (command "schemat"))
  (auto-format #t)
  (language-servers '("steel-language-server")))
