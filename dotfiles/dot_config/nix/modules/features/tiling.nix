{
  config,
  lib,
  pkgs,
  user ? { tilingWm = "yabai"; },
  ...
}:

let
  cfg = config.conf.features.tiling;
  isDarwin = pkgs.stdenv.isDarwin;
  wm = user.tilingWm or "yabai";
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

      conf.packages.darwinTaps = lib.optionals isDarwin [
        "FelixKratz/formulae"
        "koekeishiya/formulae"
        "nikitabobko/tap"
        "glzr-io/tap"
        "lgug2z/tap"
      ];

      conf.packages.darwinBrews = lib.optionals isDarwin (lib.flatten [
        { name = "FelixKratz/formulae/borders"; restart_service = false; }
        (lib.optionals (wm == "yabai") [
          { name = "koekeishiya/formulae/yabai"; }
          { name = "koekeishiya/formulae/skhd"; }
        ])
        (lib.optionals (wm == "komorebi") [
          { name = "koekeishiya/formulae/skhd"; }
          { name = "lgug2z/tap/komorebi-for-mac"; }
        ])
      ]);

      conf.packages.darwinCasks = lib.optionals isDarwin (lib.flatten [
        (lib.optionals (wm == "aerospace") [ "nikitabobko/tap/aerospace" ])
        (lib.optionals (wm == "glazewm") [ "glzr-io/tap/glazewm" "glzr-io/tap/zebar" ])
      ]);

      conf.darwin.activationScripts = lib.optionalAttrs (isDarwin && wm == "yabai") {
        yabaiSudoExtra = ''
          if ! sudo grep -q 'yabai --load-sa' /private/etc/sudoers.d/yabai 2>/dev/null; then
            echo "$(whoami) ALL=(root) NOPASSWD: /opt/homebrew/bin/yabai --load-sa" \
              | sudo tee /private/etc/sudoers.d/yabai > /dev/null
          fi
        '';
      };
    })
  ];
}
