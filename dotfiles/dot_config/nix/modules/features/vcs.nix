{ pkgs, lib, ... }:
{
  description = "Version control tooling";
  category    = "vcs";
  packages = {
    nix = with pkgs;
      [ git gh jujutsu jjui delta gnupg ]
      ++ lib.optionals pkgs.stdenv.isDarwin   [ pinentry_mac ]
      ++ lib.optionals pkgs.stdenv.isLinux    [ pinentry-gnome3 ];
  };
}
