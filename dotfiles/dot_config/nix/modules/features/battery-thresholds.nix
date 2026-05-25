{ config, lib, pkgs, ... }:

let cfg = config.conf.features.battery-thresholds;
in

{
  options.conf.features.battery-thresholds.enable =
    lib.mkEnableOption "battery charge threshold management";

  config = lib.mkMerge [
    {
      conf.featureRegistry.battery-thresholds = {
        description = "Battery charge threshold management";
        category    = "system";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.darwinCasks = lib.optionals pkgs.stdenv.isDarwin [ "aldente" ];
    })
  ];
}
