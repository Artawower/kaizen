{ config, lib, ... }:

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
  ];

  darwinCasks = [ "zen" ];
}
