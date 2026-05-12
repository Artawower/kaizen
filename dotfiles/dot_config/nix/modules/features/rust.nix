{ config, lib, pkgs, ... }:

let
  cfg = config.conf.features.rust;
in

{
  options.conf.features.rust.enable = lib.mkEnableOption "Rust toolchain";

  config = lib.mkMerge [
    {
      conf.featureRegistry.rust = {
        description = "Rust toolchain + cargo utilities";
        category    = "dev";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.nix = with pkgs; [
        rustup gcc cmake pkg-config llvmPackages.libclang
      ];
    })
  ];
}
