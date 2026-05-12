{ config, lib, pkgs, ... }:

let
  cfg = config.conf.features.python;
in

{
  options.conf.features.python.enable = lib.mkEnableOption "Python development tooling";

  config = lib.mkMerge [
    {
      conf.featureRegistry.python = {
        description = "Python development tooling";
        category    = "dev";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.nix = with pkgs; [ python3 uv ];
    })
  ];
}
