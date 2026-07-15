{
  pkgs,
  lib,
  user ? {
    tilingWm = "yabai";
  },
  ...
}:
let
  wm = user.tilingWm or "yabai";
  omniwmInstaller = ''
    target="/Applications/OmniWM.app"
    user_target="${user.homeDirectory}/Applications/OmniWM.app"
    if [ ! -d "$target" ] && [ ! -d "$user_target" ]; then
      if [ "$(uname -m)" != "arm64" ]; then
        echo "OmniWM requires Apple Silicon" >&2
        exit 1
      fi
      if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]; then
        echo "OmniWM requires macOS 26 or newer" >&2
        exit 1
      fi
      tmp_dir="$(mktemp -d)"
      trap 'rm -rf "$tmp_dir"' EXIT
      archive="$tmp_dir/OmniWM.zip"
      curl -fsSL "https://github.com/BarutSRB/OmniWM/releases/download/v0.5.6/OmniWM-v0.5.6.zip" -o "$archive"
      printf '%s  %s\n' "1a3365d625c21238c6314d7b17757725efdcddf4e2c23147c09cf3249703a3a5" "$archive" | shasum -a 256 -c -
      ditto -x -k "$archive" "$tmp_dir"
      mv "$tmp_dir/OmniWM.app" "$target"
    fi
  '';
in
{
  description = "Tiling window manager";
  category = "desktop";
  packages = {
    linux.nix = with pkgs; [
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
    ];
    darwin.taps = [
      "FelixKratz/formulae"
      "koekeishiya/formulae"
      "nikitabobko/tap"
      "glzr-io/tap"
      "lgug2z/tap"
    ];
    darwin.brews = lib.flatten [
      {
        name = "FelixKratz/formulae/borders";
        restart_service = false;
      }
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
      (lib.optionals (wm == "glazewm") [
        "glzr-io/tap/glazewm"
        "glzr-io/tap/zebar"
      ])
    ];
  };
  activation.darwin =
    (lib.optionalAttrs (wm == "yabai") {
      yabaiSudoExtra = ''
        if ! sudo grep -q 'yabai --load-sa' /private/etc/sudoers.d/yabai 2>/dev/null; then
          echo "$(whoami) ALL=(root) NOPASSWD: /opt/homebrew/bin/yabai --load-sa" \
            | sudo tee /private/etc/sudoers.d/yabai > /dev/null
        fi
      '';
    })
    // (lib.optionalAttrs (wm == "omniwm") {
      omniwmInstall = omniwmInstaller;
    });
}
