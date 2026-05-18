{
  lib,
  pkgs,
  user,
}:
{
  darwinTaps = [
    "koekeishiya/formulae"
    "FelixKratz/formulae"
  ];
  darwinBrews = [
    { name = "koekeishiya/formulae/yabai"; }
    { name = "koekeishiya/formulae/skhd"; }
    {
      name = "FelixKratz/formulae/borders";
      restart_service = false;
    }
  ];
  darwinCasks = [ ];
  darwinActivationScripts = {
    yabaiSudoExtra = ''
      if ! sudo grep -q 'yabai --load-sa' /private/etc/sudoers.d/yabai 2>/dev/null; then
        echo "$(whoami) ALL=(root) NOPASSWD: /opt/homebrew/bin/yabai --load-sa" \
          | sudo tee /private/etc/sudoers.d/yabai > /dev/null
      fi
    '';
  };
}
