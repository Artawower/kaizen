{ config, lib, pkgs, ... }:

let cfg = config.conf.features.python; in

{
  config = lib.mkIf cfg.enable {
    conf.packages.nix = with pkgs; [
      python3
      uv
    ];
  };
}
