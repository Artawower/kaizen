{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.conf.features.emacs;
  isDarwin = pkgs.stdenv.isDarwin;
in

{
  config = lib.mkIf cfg.enable {
    conf.packages.nix =
      with pkgs;
      [
        imagemagick
        tree-sitter
      ]
      ++ lib.optionals (!isDarwin) [
        emacs
        enchant_2
        pkg-config
        isync
        msmtp
        cacert
      ];
  };
}
