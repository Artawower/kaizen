{ pkgs, lib, user ? { tilingWm = "yabai"; }, ... }:
let
  wm = user.tilingWm or "yabai";
in
{
  description = "Tiling window manager";
  category    = "desktop";
  packages = {
    linux.nix = with pkgs; [
      niri xremap xwayland-satellite wl-clipboard wl-clip-persist
      wl-screenrec waybar swww fuzzel swaynotificationcenter
      brightnessctl playerctl grim slurp swappy
    ];
    darwin.taps = [
      "FelixKratz/formulae" "koekeishiya/formulae" "nikitabobko/tap"
      "glzr-io/tap" "lgug2z/tap"
    ];
    darwin.brews = lib.flatten [
      { name = "FelixKratz/formulae/borders"; restart_service = false; }
      (lib.optionals (wm == "yabai") [
        { name = "koekeishiya/formulae/yabai"; }
        { name = "koekeishiya/formulae/skhd"; }
      ])
      (lib.optionals (wm == "komorebi") [
        { name = "koekeishiya/formulae/skhd"; }
        { name = "lgug2z/tap/komorebi-for-mac"; }
      ])
    ];
    darwin.casks = lib.flatten [
      (lib.optionals (wm == "aerospace") [ "nikitabobko/tap/aerospace" ])
      (lib.optionals (wm == "glazewm")   [ "glzr-io/tap/glazewm" "glzr-io/tap/zebar" ])
    ];
  };
  activation.darwin = lib.optionalAttrs (wm == "yabai") {
    yabaiSudoExtra = ''
      if ! sudo grep -q 'yabai --load-sa' /private/etc/sudoers.d/yabai 2>/dev/null; then
        echo "$(whoami) ALL=(root) NOPASSWD: /opt/homebrew/bin/yabai --load-sa" \
          | sudo tee /private/etc/sudoers.d/yabai > /dev/null
      fi
    '';
  };
}
