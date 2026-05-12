{ user, lib, ... }:

let
  dataPath = "${builtins.getEnv "HOME"}/.config/kaizen/data.toml";
  data =
    if builtins.pathExists dataPath
    then builtins.fromTOML (builtins.readFile dataPath)
    else { layout = "qwerty"; features = { }; };
in

{
  imports = [ ../modules/darwin.nix ];

  home.stateVersion         = "23.05";
  home.username             = user.username;
  home.homeDirectory        = "/Users/${user.username}";
  programs.home-manager.enable = true;

  conf.layout    = data.layout;
  conf.features  = lib.mapAttrs (_: enabled: { enable = enabled; }) data.features;
}
