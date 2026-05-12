{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.conf.features.tiling;
  isDarwin = pkgs.stdenv.isDarwin;
in

{
  options.conf.features.tiling.enable = lib.mkEnableOption "tiling window manager";

  config = lib.mkMerge [
    {
      conf.featureRegistry.tiling = {
        description = "Tiling window manager";
        category = "desktop";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.nix = lib.optionals (!isDarwin) (
        with pkgs;
        [
          niri
          xremap
          xwayland-satellite
          wl-clipboard
          wl-clip-persist
          wl-screenrec
          waybar
          swww
          fuzzel
          swaynotificationcenter
          brightnessctl
          playerctl
          grim
          slurp
          swappy
        ]
      );
    })
  ];

  darwinTaps = [
    "koekeishiya/formulae"
    "FelixKratz/formulae"
    "nikitabobko/tap"
  ];
  darwinBrews = [
    { name = "koekeishiya/formulae/yabai"; }
    { name = "koekeishiya/formulae/skhd"; }
    {
      name = "FelixKratz/formulae/borders";
      restart_service = false;
    }
  ];
  darwinCasks = [ "nikitabobko/tap/aerospace" ];
}
