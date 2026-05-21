(declare-module "nix"
  :os          '(darwin linux)
  :group       'package-manager
  :description "Nix package manager")

(on-bump!
  (lambda ()
    (shell! "nix flake update --flake ~/.config/nix")))

(on-re-add!
  (lambda ()
    (chezmoi-re-add! "~/.config/nix/flake.lock")))
