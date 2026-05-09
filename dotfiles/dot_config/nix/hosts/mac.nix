{ user, ... }:

let
  dataPath = "${builtins.getEnv "HOME"}/.config/kaizen/data.toml";
  data = if builtins.pathExists dataPath
    then builtins.fromTOML (builtins.readFile dataPath)
    else { layout = "qwerty"; features = {
        core = false; vcs = false; terminal = false; emacs = false;
        keyboard = false; frontend = false; go = false; python = false;
        rust = false; ai = false; tiling = false;
      }; };
in

{
  imports = [ ../modules/darwin.nix ];

  home.stateVersion    = "23.05";
  home.username        = user.username;
  home.homeDirectory   = "/Users/${user.username}";
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
}
