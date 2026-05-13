{ lib, ... }:

{
  options.conf = {
    layout = lib.mkOption {
      type    = lib.types.enum [ "qwerty" "colemak" ];
      default = "qwerty";
    };

    featureRegistry = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          description = lib.mkOption { type = lib.types.str; default = ""; };
          category    = lib.mkOption { type = lib.types.str; default = ""; };
        };
      });
      default = { };
    };

    packages.nix = lib.mkOption {
      type    = lib.types.listOf lib.types.package;
      default = [ ];
    };
  };
}
