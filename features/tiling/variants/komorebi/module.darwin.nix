{
  lib,
  pkgs,
  user,
}:
{
  darwinTaps = [ "lgug2z/tap" ];
  darwinBrews = [
    { name = "lgug2z/tap/komorebi-for-mac"; }
    { name = "koekeishiya/formulae/skhd"; }
    {
      name = "FelixKratz/formulae/borders";
      restart_service = false;
    }
  ];
  darwinCasks = [ ];
  darwinActivationScripts = { };
}
