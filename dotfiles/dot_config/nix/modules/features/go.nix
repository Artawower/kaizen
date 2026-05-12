{ config, lib, pkgs, ... }:

let
  cfg = config.conf.features.go;
in

{
  options.conf.features.go.enable = lib.mkEnableOption "Go development tooling";

  config = lib.mkMerge [
    {
      conf.featureRegistry.go = {
        description = "Go development tooling";
        category    = "dev";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.nix = with pkgs; [ go gopls go-tools ];
    })
  ];
}
