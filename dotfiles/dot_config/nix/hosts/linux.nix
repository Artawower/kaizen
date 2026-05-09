{ inputs, pkgs, user, ... }:

let
  data = builtins.fromTOML (builtins.readFile "${builtins.getEnv "HOME"}/.local/share/chezmoi/.chezmoidata.toml");
in

{
  imports = [
    ../modules/linux.nix
    ../modules/features/battery-thresholds.nix
  ];

  home.stateVersion  = "25.11";
  home.username      = user.username;
  home.homeDirectory = "/home/${user.username}";
  programs.home-manager.enable = true;

  conf.layout = data.layout;

  conf.features = {
    core.enable     = data.features.core;
    vcs.enable      = data.features.vcs;
    terminal.enable = data.features.terminal;
    emacs.enable    = data.features.emacs;
    keyboard.enable = data.features.keyboard;
    frontend.enable = data.features.frontend;
    go.enable       = data.features.go;
    python.enable   = data.features.python;
    rust.enable     = data.features.rust;
    ai.enable       = data.features.ai;
    tiling.enable   = data.features.tiling;
  };

  home.packages = [
    inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell
  ];
}
