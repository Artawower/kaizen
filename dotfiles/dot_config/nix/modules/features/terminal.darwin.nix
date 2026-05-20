{ lib, ... }:
{
  darwinCasks = [
    "ghostty"
    "wezterm"
    "neohtop"
    "cmux"
    "muxy"
  ];
  darwinTaps = [ "muxy-app/tap" ];
}
