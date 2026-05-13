{ config, lib, ... }:

let
  cfg = config.conf.features.desktop;
in

{
  options.conf.features.desktop.enable = lib.mkEnableOption "desktop utilities";

  config = lib.mkMerge [
    {
      conf.featureRegistry.desktop = {
        description = "Desktop utilities: launcher, menu bar, file manager, cleaner";
        category = "desktop";
      };
    }
  ];
}
