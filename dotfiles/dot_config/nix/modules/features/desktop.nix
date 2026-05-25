{ config, lib, pkgs, ... }:

let cfg = config.conf.features.desktop;
in

{
  options.conf.features.desktop.enable = lib.mkEnableOption "desktop utilities";

  config = lib.mkMerge [
    {
      conf.featureRegistry.desktop = {
        description = "Desktop utilities: launcher, menu bar, file manager, cleaner";
        category    = "desktop";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.darwinCasks = lib.optionals pkgs.stdenv.isDarwin [
        "raycast"
        "jordanbaird-ice"
        "stats"
        "clop"
        "marta"
        "pearcleaner"
      ];
    })
  ];
}
