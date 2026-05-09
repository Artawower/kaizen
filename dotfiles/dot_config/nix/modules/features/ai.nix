{ config, lib, pkgs, ... }:

let cfg = config.conf.features.ai; in

{
  config = lib.mkIf cfg.enable {
    conf.packages.nix = with pkgs; [
      podman
    ];
  };
}
