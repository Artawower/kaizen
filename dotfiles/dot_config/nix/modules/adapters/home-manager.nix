{
  config,
  lib,
  pkgs,
  ...
}:

{
  home.packages = lib.unique (
    config.conf.packages.nix ++ map (n: pkgs.${n}) config.conf.extra.nixPackages
  );
}
