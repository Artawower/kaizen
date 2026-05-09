{ config, lib, pkgs, ... }:

let cfg = config.conf.features.rust; in

{
  config = lib.mkIf cfg.enable {
    conf.packages.nix = with pkgs; [
      rustup
      gcc
      cmake
      pkg-config
      llvmPackages.libclang
    ];
  };
}
