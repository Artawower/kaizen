{
  config,
  lib,
  pkgs,
  ...
}:

let
  resolveExtraPackage =
    name:
    if lib.hasAttr name pkgs then
      pkgs.${name}
    else
      throw "[extra].nix_packages: \"${name}\" is not a top-level nixpkgs attribute. Check the spelling or use a user-features/*.nix module for nested packages.";
in

{
  home.packages = lib.unique (
    config.conf.packages.nix ++ map resolveExtraPackage config.conf.extra.nixPackages
  );
}
