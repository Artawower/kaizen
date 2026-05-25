{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.conf.features.media;
  isLinux = pkgs.stdenv.isLinux;
in

{
  options.conf.features.media.enable = lib.mkEnableOption "media players";

  config = lib.mkMerge [
    {
      conf.featureRegistry.media = {
        description = "Media players: VLC, Spotube";
        category = "media";
      };
    }
    (lib.mkIf (cfg.enable && isLinux) {
      conf.packages.nix = with pkgs; [ vlc ];
    })
    (lib.mkIf cfg.enable {
      conf.packages.darwinCasks = lib.optionals pkgs.stdenv.isDarwin [ "vlc" "krtirtho/apps/spotube" ];
      conf.packages.darwinTaps  = lib.optionals pkgs.stdenv.isDarwin [ "krtirtho/apps" ];
    })
  ];
}
