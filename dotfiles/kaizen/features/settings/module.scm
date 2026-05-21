(declare-module "settings" :group 'system :description "Global settings")

(set-global! :layout       "colemak")
(set-global! :ui/font-size "18")
(set-global! :ui/theme     "catppuccin-mocha")

(on-bump!
  (lambda ()
    (shell! "~/.config/scripts/mise-bump")))

(on-re-add!
  (lambda ()
    (chezmoi-re-add! "~/.config/mise.lock")))
