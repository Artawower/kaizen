{ config, lib, pkgs, ... }:

let cfg = config.conf.features.screencast;
in

{
  options.conf.features.screencast.enable = lib.mkEnableOption "screencasting and demo tools";

  config = lib.mkMerge [
    {
      conf.featureRegistry.screencast = {
        description = "Screencasting and demo tools: LICEcap, KeyCastr";
        category    = "dev";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.darwinCasks = lib.optionals pkgs.stdenv.isDarwin [ "licecap" "keycastr" ];
    })
  ];
}
