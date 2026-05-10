{ lib, ... }:

let
  manifestPath = builtins.toPath (builtins.getEnv "HOME" + "/.config/kaizen/manifest.toml");

  defaultFeatures = [
    { name = "core";     description = "core CLI tools"; }
    { name = "vcs";      description = "version control tooling"; }
    { name = "terminal"; description = "terminal, TUI tools, and shell"; }
    { name = "emacs";    description = "Emacs editor"; }
    { name = "keyboard"; description = "keyboard layout tooling"; }
    { name = "frontend"; description = "frontend development tooling"; }
    { name = "go";       description = "Go development tooling"; }
    { name = "python";   description = "Python development tooling"; }
    { name = "rust";     description = "Rust development tooling"; }
    { name = "ai";       description = "AI coding agents"; }
    { name = "tiling";   description = "tiling window manager"; }
  ];

  features =
    if builtins.pathExists manifestPath
    then (builtins.fromTOML (builtins.readFile manifestPath)).features
    else defaultFeatures;
in

{
  options.conf = {
    layout = lib.mkOption {
      type    = lib.types.enum [ "qwerty" "colemak" ];
      default = "qwerty";
    };

    features = builtins.listToAttrs (map (f: {
      name  = f.name;
      value.enable = lib.mkEnableOption f.description;
    }) features);

    packages = {
      nix = lib.mkOption {
        type    = lib.types.listOf lib.types.package;
        default = [];
      };
    };
  };
}
