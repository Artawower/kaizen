{ config, lib, pkgs, ... }:

let
  cfg      = config.conf.features.keyboard;
  isDarwin = pkgs.stdenv.isDarwin;
in

{
  options.conf.features.keyboard.enable = lib.mkEnableOption "keyboard layout tooling";

  config = lib.mkMerge [
    {
      conf.featureRegistry.keyboard = {
        description = "Keyboard layout tooling";
        category    = "system";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.nix = lib.optionals (!isDarwin) (with pkgs; [ xremap ]);
    })
  ];
}
