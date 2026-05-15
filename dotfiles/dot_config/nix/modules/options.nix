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
            updateHooks = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    run = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                    };
                    onFailure = lib.mkOption {
                      type = lib.types.enum [
                        "warn"
                        "fail"
                      ];
                      default = "warn";
                    };
                  };
                }
              );
              default = [ ];
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

    ui.fontSize = lib.mkOption {
      type = lib.types.float;
      default = 14.0;
      description = "Global UI font size from data.toml [ui].font_size";
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
