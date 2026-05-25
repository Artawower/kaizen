{ config, lib, pkgs, ... }:

let cfg = config.conf.features.api;
in

{
  options.conf.features.api.enable = lib.mkEnableOption "API client tools";

  config = lib.mkMerge [
    {
      conf.featureRegistry.api = {
        description = "API client tools: Hoppscotch";
        category    = "dev";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.darwinCasks = lib.optionals pkgs.stdenv.isDarwin [ "hoppscotch" ];
    })
  ];
}
