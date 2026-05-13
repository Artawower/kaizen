{ lib, ... }: {
  darwinTaps  = [ "koekeishiya/formulae" "FelixKratz/formulae" "nikitabobko/tap" ];
  darwinBrews = [
    { name = "koekeishiya/formulae/yabai"; }
    { name = "koekeishiya/formulae/skhd"; }
    { name = "FelixKratz/formulae/borders"; restart_service = false; }
  ];
  darwinCasks = [ "nikitabobko/tap/aerospace" ];
}
