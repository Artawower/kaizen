{ lib, ... }:

{
  options.conf = {
    layout = lib.mkOption {
      type = lib.types.enum [ "qwerty" "colemak" ];
      default = "qwerty";
    };

    features = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.enable = lib.mkEnableOption "feature";
      });
      default = { };
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

    packages = {
      nix = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
      };

      brewCasks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
  };
}
