{ config, lib, pkgs, ... }:

let
  cfg = config.conf.features.core;
in

{
  options.conf.features.core.enable = lib.mkEnableOption "core CLI utilities";

  config = lib.mkMerge [
    {
      conf.featureRegistry.core = {
        description = "Core CLI utilities";
        category    = "system";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.nix = with pkgs; [
        ripgrep fd fzf jq tree curl wget unzip
        coreutils dash htop ncdu sqlite just mise
        nil pandoc marksman yaml-language-server multimarkdown
      ];
    })
  ];
}
