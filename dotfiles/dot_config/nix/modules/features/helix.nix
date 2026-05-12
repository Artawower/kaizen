{ config, lib, pkgs, ... }:

let
  cfg = config.conf.features.helix;
in

{
  options.conf.features.helix.enable = lib.mkEnableOption "Helix editor + LSP";

  config = lib.mkMerge [
    {
      conf.featureRegistry.helix = {
        description = "Helix editor + marksman LSP";
        category    = "editor";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.nix = with pkgs; [ helix marksman ];
    })
  ];
}
