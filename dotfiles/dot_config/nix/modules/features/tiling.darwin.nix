{
  lib,
  pkgs,
  user,
}:
let
  wm = user.tilingWm or "yabai";
in
{
  darwinTaps = [
    "FelixKratz/formulae"
    "koekeishiya/formulae"
    "nikitabobko/tap"
    "glzr-io/tap"
  ];

  darwinBrews = lib.flatten [
    {
      name = "FelixKratz/formulae/borders";
      restart_service = false;
    }
    (lib.optionals (wm == "yabai") [
      { name = "koekeishiya/formulae/yabai"; }
      { name = "koekeishiya/formulae/skhd"; }
    ])
  ];

  darwinCasks = lib.flatten [
    (lib.optionals (wm == "aerospace") [ "nikitabobko/tap/aerospace" ])
    (lib.optionals (wm == "glazewm") [
      "glzr-io/tap/glazewm"
      "glzr-io/tap/zebar"
    ])
  ];

  darwinActivationScripts = lib.optionalAttrs (wm == "yabai") {
    yabaiSudoExtra = ''
      if ! sudo grep -q 'yabai --load-sa' /private/etc/sudoers.d/yabai 2>/dev/null; then
        echo "$(whoami) ALL=(root) NOPASSWD: /opt/homebrew/bin/yabai --load-sa" \
          | sudo tee /private/etc/sudoers.d/yabai > /dev/null
      fi
    '';
  };
}
