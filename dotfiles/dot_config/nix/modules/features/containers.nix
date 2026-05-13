{ config, lib, pkgs, ... }:

let
  cfg     = config.conf.features.containers;
  isLinux = pkgs.stdenv.isLinux;
in

{
  options.conf.features.containers.enable = lib.mkEnableOption "container and VM tooling";

  config = lib.mkMerge [
    {
      conf.featureRegistry.containers = {
        description = "Container and VM tooling: OrbStack";
        category    = "dev";
      };
    }
    (lib.mkIf (cfg.enable && isLinux) {
      conf.packages.nix = with pkgs; [ podman ];
    })
  ];
}
