{ ... }:

{
  imports = [
    ./options.nix
    ./adapters/home-manager.nix
    ./features/core.nix
    ./features/vcs.nix
    ./features/terminal.nix
    ./features/emacs.nix
    ./features/keyboard.nix
    ./features/frontend.nix
    ./features/go.nix
    ./features/python.nix
    ./features/rust.nix
    ./features/ai.nix
    ./features/tiling.nix
    ./features/darkman.nix
    ./features/fonts.nix
  ];
}
