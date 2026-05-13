{ lib, ... }:

{
  options.conf = {
    layout = lib.mkOption {
      type = lib.types.enum [
        "qwerty"
        "colemak"
      ];
      default = "qwerty";
    };

    featureRegistry = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            description = lib.mkOption {
              type = lib.types.str;
              default = "";
            };
            category = lib.mkOption {
              type = lib.types.str;
              default = "";
            };
          };
        }
      );
      default = { };
    };

    packages.nix = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
    };

    extra = {
      nixPackages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Top-level nixpkgs attribute names from data.toml [extra].nix_packages";
      };
      brewCasks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      brewFormulas = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      brewTaps = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
  };
}
