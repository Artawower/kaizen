{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.conf.features.frontend;
in

{
  config = lib.mkIf cfg.enable {
    conf.packages.nix = with pkgs; [
      lua-language-server
      google-java-format
    ];
  };
}
