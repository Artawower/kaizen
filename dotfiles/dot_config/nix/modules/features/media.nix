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
  ];
}
