{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.conf.features.vcs;
  isDarwin = pkgs.stdenv.isDarwin;
in

{
  config = lib.mkIf cfg.enable {
    conf.packages.nix =
      with pkgs;
      [
        git
        gh
        jujutsu
        jjui
        delta
        gnupg
      ]
      ++ lib.optionals isDarwin [
        pinentry_mac
      ]
      ++ lib.optionals (!isDarwin) [
        pinentry-gnome3
      ];
  };
}
