{ config, lib, pkgs, ... }:

let
  cfg      = config.conf.features.vcs;
  isDarwin = pkgs.stdenv.isDarwin;
in

{
  options.conf.features.vcs.enable = lib.mkEnableOption "version control tooling";

  config = lib.mkMerge [
    {
      conf.featureRegistry.vcs = {
        description = "Version control tooling";
        category    = "vcs";
      };
    }
    (lib.mkIf cfg.enable {
      conf.packages.nix =
        with pkgs;
        [ git gh jujutsu jjui delta gnupg ]
        ++ lib.optionals isDarwin   [ pinentry_mac ]
        ++ lib.optionals (!isDarwin) [ pinentry-gnome3 ];
    })
  ];
}
