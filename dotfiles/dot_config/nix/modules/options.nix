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
                    run = lib.mkOption { type = lib.types.listOf lib.types.str; };
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

            update = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    run = lib.mkOption { type = lib.types.listOf lib.types.str; };
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

            bump = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  before = lib.mkOption {
                    type = lib.types.listOf (
                      lib.types.submodule {
                        options = {
                          run = lib.mkOption { type = lib.types.listOf lib.types.str; };
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
                  run = lib.mkOption {
                    type = lib.types.listOf (
                      lib.types.submodule {
                        options = {
                          run = lib.mkOption { type = lib.types.listOf lib.types.str; };
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
                  capture = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                  };
                };
              };
              default = { };
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

    packages.darwinBrews = lib.mkOption {
      type = lib.types.listOf lib.types.anything;
      default = [ ];
      description = "Homebrew brews contributed by features (merged into homebrew.brews)";
    };

    packages.darwinCasks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Homebrew casks contributed by features";
    };

    packages.darwinTaps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Homebrew taps contributed by features";
    };

    packages.darwinBrewFormulas = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Homebrew extraConfig lines contributed by features";
    };

    darwin.activationScripts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Darwin activation script bodies contributed by features (map name -> shell text).
        Keys must be globally unique across all features: use feature-scoped prefixes
        (e.g. "emacsApp", "yabaiSudoExtra") to avoid conflicts.
        Duplicate keys cause a Nix module system type error.
      '';
    };
  };
}
