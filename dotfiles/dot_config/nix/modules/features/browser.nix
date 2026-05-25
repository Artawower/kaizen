{ config, lib, pkgs, ... }:

let cfg = config.conf.features.browser;
in

{
  options.conf.features.browser.enable = lib.mkEnableOption "web browser";

  config = lib.mkMerge [
    {
      conf.featureRegistry.browser = {
        description = "Web browser: Zen";
        category    = "desktop";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.darwinCasks = lib.optionals pkgs.stdenv.isDarwin [ "zen" ];
    })
  ];
}
