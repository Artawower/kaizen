{ config, lib, pkgs, ... }:

let cfg = config.conf.features.go; in

{
  config = lib.mkIf cfg.enable {
    conf.packages.nix = with pkgs; [
      go
      gopls
      go-tools
    ];
  };
}
