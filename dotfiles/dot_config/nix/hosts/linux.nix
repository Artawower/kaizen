{
  inputs,
  pkgs,
  user,
  lib,
  ...
}:

let
  dataPath = "${builtins.getEnv "HOME"}/.config/kaizen/data.toml";
  data =
    if builtins.pathExists dataPath then
      builtins.fromTOML (builtins.readFile dataPath)
    else
      {
        layout = "qwerty";
        features = { };
      };
  extra = data.extra or { };
in

{
  imports = [ ../modules/linux.nix ];

  home.stateVersion = "25.11";
  home.username = user.username;
  home.homeDirectory = "/home/${user.username}";
  programs.home-manager.enable = true;

  conf.layout = data.layout;
  conf.features = lib.mapAttrs (_: enabled: { enable = enabled; }) data.features;

  conf.extra = {
    nixPackages = extra.nix_packages or [ ];
    brewCasks = extra.brew_casks or [ ];
    brewFormulas = extra.brew_formulas or [ ];
    brewTaps = extra.brew_taps or [ ];
  };

  home.packages = [
    inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell
  ];
}
