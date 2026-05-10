{ lib, ... }:

let
  manifest = builtins.fromTOML (builtins.readFile ../../../kaizen/manifest.toml);
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
    }) manifest.features);

    packages = {
      nix = lib.mkOption {
        type    = lib.types.listOf lib.types.package;
        default = [];
      };
    };
  };
}
