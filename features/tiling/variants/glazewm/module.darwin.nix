{
  lib,
  pkgs,
  user,
}:
{
  darwinTaps = [ "glzr-io/tap" ];
  darwinBrews = [ ];
  darwinCasks = [
    "glzr-io/tap/glazewm"
    "glzr-io/tap/zebar"
  ];
  darwinActivationScripts = { };
}
