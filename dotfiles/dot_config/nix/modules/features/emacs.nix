{ config, lib, pkgs, ... }:

let
  cfg      = config.conf.features.emacs;
  isDarwin = pkgs.stdenv.isDarwin;
in

{
  options.conf.features.emacs.enable = lib.mkEnableOption "Emacs editor";

  config = lib.mkMerge [
    {
      conf.featureRegistry.emacs = {
        description = "Emacs editor";
        category    = "editor";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.nix =
        with pkgs;
        [ imagemagick tree-sitter ]
        ++ lib.optionals (!isDarwin) [
          emacs enchant_2 pkg-config isync msmtp cacert
        ];
    })
  ];
}
